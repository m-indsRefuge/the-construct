(* ::Package:: *)

BeginPackage["TheConstruct`"];

TCProgram::usage =
    "TCProgram[p1,p2,...] is the symbolic executable genome of a Construct inhabitant.";

AvailablePrimitives::usage =
    "AvailablePrimitives[] returns the primitive computational vocabulary.";

ValidGenomeQ::usage =
    "ValidGenomeQ[genome] checks whether a symbolic genome can execute.";

ExecuteGenome::usage =
    "ExecuteGenome[genome,input] executes a symbolic genome on an input.";

MutateGenome::usage =
    "MutateGenome[genome,spec] rewrites a symbolic genome.";

CreateInhabitant::usage =
    "CreateInhabitant[world,id,genome,parents] creates a computational inhabitant.";

ExecuteInhabitant::usage =
    "ExecuteInhabitant[world,id,input] executes an inhabitant and returns World and Output.";

MutateInhabitant::usage =
    "MutateInhabitant[world,parent,child,spec] creates a rewritten descendant.";

ComposeInhabitants::usage =
    "ComposeInhabitants[world,parents,child] combines inhabitants into a larger program.";

InhabitantSummary::usage =
    "InhabitantSummary[world,id] returns compact inhabitant state.";

PopulationSummary::usage =
    "PopulationSummary[world] returns compact summaries for all inhabitants.";

Begin["`Private`"];

$TCPrimitives = {
    "Identity",
    "Increment",
    "Decrement",
    "Double",
    "Negate",
    "Square",
    "Abs",
    "Mod10"
};

AvailablePrimitives[] := $TCPrimitives;

ValidGenomeQ[TCProgram[ops___]] :=
    AllTrue[{ops}, MemberQ[$TCPrimitives, #] &];

ValidGenomeQ[_] := False;

ApplyPrimitive[value_, "Identity"] := value;
ApplyPrimitive[value_, "Increment"] := value + 1;
ApplyPrimitive[value_, "Decrement"] := value - 1;
ApplyPrimitive[value_, "Double"] := 2 value;
ApplyPrimitive[value_, "Negate"] := -value;
ApplyPrimitive[value_, "Square"] := value^2;
ApplyPrimitive[value_, "Abs"] := Abs[value];
ApplyPrimitive[value_, "Mod10"] := Mod[value, 10];

ExecuteGenome[genome_TCProgram, input_] /; ValidGenomeQ[genome] :=
    Fold[ApplyPrimitive, input, List @@ genome];

ExecuteGenome[genome_, _] :=
    Failure[
        "InvalidGenome",
        <|"Genome" -> HoldForm[genome]|>
    ];

MutateGenome[
    genome_TCProgram,
    spec_Association
] /; ValidGenomeQ[genome] :=
    Module[
        {
            operations = List @@ genome,
            operation,
            primitive,
            position
        },

        operation = Lookup[spec, "Operation", "Insert"];
        primitive = Lookup[spec, "Primitive", "Identity"];
        position = Lookup[spec, "Position", Length[operations] + 1];

        Switch[
            operation,

            "Insert",
            If[
                !MemberQ[$TCPrimitives, primitive],
                Return[
                    Failure[
                        "UnknownPrimitive",
                        <|"Primitive" -> primitive|>
                    ]
                ]
            ];
            Apply[
                TCProgram,
                Insert[
                    operations,
                    primitive,
                    Clip[position, {1, Length[operations] + 1}]
                ]
            ],

            "Replace",
            If[
                !MemberQ[$TCPrimitives, primitive] ||
                Length[operations] == 0,
                Return[
                    Failure[
                        "InvalidMutation",
                        <|"Specification" -> spec|>
                    ]
                ]
            ];
            Apply[
                TCProgram,
                ReplacePart[
                    operations,
                    Clip[position, {1, Length[operations]}] -> primitive
                ]
            ],

            "Delete",
            If[
                Length[operations] <= 1,
                Return[
                    Failure[
                        "GenomeTooSmall",
                        <|"Genome" -> genome|>
                    ]
                ]
            ];
            Apply[
                TCProgram,
                Delete[
                    operations,
                    Clip[position, {1, Length[operations]}]
                ]
            ],

            _,
            Failure[
                "UnknownMutation",
                <|"Operation" -> operation|>
            ]
        ]
    ];

NormalizeParents[None] := {};
NormalizeParents[parent_String] := {parent};
NormalizeParents[parents_List] := parents;

CreateInhabitant[
    world_Association,
    id_String,
    genome_TCProgram,
    parentSpec_: None
] :=
    Module[
        {
            parents,
            parentRecords,
            generation,
            registered,
            baseRecord,
            record,
            next
        },

        If[
            !ValidGenomeQ[genome],
            Return[
                Failure[
                    "InvalidGenome",
                    <|"Genome" -> genome|>
                ]
            ]
        ];

        If[
            KeyExistsQ[world["Processes"], id],
            Return[
                Failure[
                    "ProcessAlreadyExists",
                    <|"ProcessID" -> id|>
                ]
            ]
        ];

        parents = NormalizeParents[parentSpec];

        parentRecords =
            Lookup[
                world["Processes"],
                parents,
                Missing["UnknownParent"]
            ];

        If[
            AnyTrue[parentRecords, MissingQ],
            Return[
                Failure[
                    "UnknownParent",
                    <|"Parents" -> parents|>
                ]
            ]
        ];

        generation =
            If[
                parents === {},
                0,
                1 + Max[Lookup[parentRecords, "Generation", 0]]
            ];

        registered =
            TheConstruct`RegisterProcess[
                world,
                id,
                "inhabitant"
            ];

        If[FailureQ[registered], Return[registered]];

        baseRecord = registered["Processes"][id];

        record =
            Join[
                baseRecord,
                <|
                    "Genome" -> genome,
                    "Generation" -> generation,
                    "Parents" -> parents,
                    "Executions" -> 0,
                    "LastInput" -> Missing["NotExecuted"],
                    "LastOutput" -> Missing["NotExecuted"]
                |>
            ];

        next =
            Join[
                registered,
                <|
                    "Processes" ->
                        Join[
                            registered["Processes"],
                            <|id -> record|>
                        ]
                |>
            ];

        TheConstruct`EmitEvent[
            next,
            "INHABITANT_CREATED",
            id,
            <|
                "Generation" -> generation,
                "Parents" -> parents,
                "Genome" -> ToString[genome, InputForm]
            |>
        ]
    ];

ExecuteInhabitant[
    world_Association,
    id_String,
    input_
] :=
    Module[
        {
            process,
            genome,
            cost,
            spent,
            output,
            updatedProcess,
            next
        },

        If[
            !KeyExistsQ[world["Processes"], id],
            Return[
                Failure[
                    "UnknownInhabitant",
                    <|"ProcessID" -> id|>
                ]
            ]
        ];

        process = world["Processes"][id];

        If[
            Lookup[process, "Kind", ""] =!= "inhabitant",
            Return[
                Failure[
                    "NotInhabitant",
                    <|"ProcessID" -> id|>
                ]
            ]
        ];

        genome = process["Genome"];
        cost = Max[1, Length[List @@ genome]];

        spent =
            TheConstruct`SpendResource[
                world,
                "Compute",
                cost,
                id
            ];

        If[FailureQ[spent], Return[spent]];

        output = ExecuteGenome[genome, input];

        If[FailureQ[output], Return[output]];

        updatedProcess =
            Join[
                process,
                <|
                    "Executions" ->
                        Lookup[process, "Executions", 0] + 1,
                    "LastInput" -> input,
                    "LastOutput" -> output
                |>
            ];

        next =
            Join[
                spent,
                <|
                    "Processes" ->
                        Join[
                            spent["Processes"],
                            <|id -> updatedProcess|>
                        ]
                |>
            ];

        next =
            TheConstruct`EmitEvent[
                next,
                "INHABITANT_EXECUTED",
                id,
                <|
                    "Input" -> input,
                    "Output" -> output,
                    "ComputeCost" -> cost
                |>
            ];

        <|
            "World" -> next,
            "Output" -> output
        |>
    ];

MutateInhabitant[
    world_Association,
    parentID_String,
    childID_String,
    spec_Association
] :=
    Module[
        {
            parent,
            before,
            after,
            spent,
            next
        },

        If[
            !KeyExistsQ[world["Processes"], parentID],
            Return[
                Failure[
                    "UnknownParent",
                    <|"Parent" -> parentID|>
                ]
            ]
        ];

        parent = world["Processes"][parentID];
        before = parent["Genome"];
        after = MutateGenome[before, spec];

        If[FailureQ[after], Return[after]];

        spent =
            TheConstruct`SpendResource[
                world,
                "Compute",
                3,
                parentID
            ];

        If[FailureQ[spent], Return[spent]];

        next =
            CreateInhabitant[
                spent,
                childID,
                after,
                parentID
            ];

        If[FailureQ[next], Return[next]];

        TheConstruct`EmitEvent[
            next,
            "GENOME_MUTATED",
            parentID,
            <|
                "Child" -> childID,
                "Specification" -> spec,
                "Before" -> ToString[before, InputForm],
                "After" -> ToString[after, InputForm]
            |>
        ]
    ];

ComposeInhabitants[
    world_Association,
    parentIDs_List,
    childID_String
] :=
    Module[
        {
            records,
            genomes,
            operations,
            genome,
            spent,
            next
        },

        If[
            Length[parentIDs] < 2,
            Return[
                Failure[
                    "NeedMultipleParents",
                    <|"Parents" -> parentIDs|>
                ]
            ]
        ];

        records =
            Lookup[
                world["Processes"],
                parentIDs,
                Missing["UnknownParent"]
            ];

        If[
            AnyTrue[records, MissingQ],
            Return[
                Failure[
                    "UnknownParent",
                    <|"Parents" -> parentIDs|>
                ]
            ]
        ];

        genomes = Lookup[records, "Genome"];

        If[
            !AllTrue[genomes, ValidGenomeQ],
            Return[
                Failure[
                    "InvalidParentGenome",
                    <|"Parents" -> parentIDs|>
                ]
            ]
        ];

        operations =
            Flatten[
                (List @@ #) & /@ genomes
            ];

        genome = Apply[TCProgram, operations];

        spent =
            TheConstruct`SpendResource[
                world,
                "Compute",
                5,
                First[parentIDs]
            ];

        If[FailureQ[spent], Return[spent]];

        next =
            CreateInhabitant[
                spent,
                childID,
                genome,
                parentIDs
            ];

        If[FailureQ[next], Return[next]];

        TheConstruct`EmitEvent[
            next,
            "INHABITANTS_COMPOSED",
            childID,
            <|
                "Parents" -> parentIDs,
                "Genome" -> ToString[genome, InputForm]
            |>
        ]
    ];

InhabitantSummary[
    world_Association,
    id_String
] :=
    Module[{process},

        If[
            !KeyExistsQ[world["Processes"], id],
            Return[
                Failure[
                    "UnknownInhabitant",
                    <|"ProcessID" -> id|>
                ]
            ]
        ];

        process = world["Processes"][id];

        <|
            "ID" -> id,
            "Generation" -> Lookup[process, "Generation", Missing[]],
            "Parents" -> Lookup[process, "Parents", {}],
            "Genome" ->
                ToString[
                    Lookup[process, "Genome", Missing[]],
                    InputForm
                ],
            "Executions" -> Lookup[process, "Executions", 0],
            "LastOutput" ->
                Lookup[
                    process,
                    "LastOutput",
                    Missing["NotExecuted"]
                ]
        |>
    ];

PopulationSummary[world_Association] :=
    InhabitantSummary[world, #] & /@
        Keys[
            Select[
                world["Processes"],
                Lookup[#, "Kind", ""] === "inhabitant" &
            ]
        ];

End[];
EndPackage[];
