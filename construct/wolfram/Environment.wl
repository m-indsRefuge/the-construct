(* ::Package:: *)

BeginPackage["TheConstruct`"];

CreateContract::usage =
    "CreateContract[world,id,examples,reward] adds a verifiable computational contract.";

SeedWorldZeroEnvironment::usage =
    "SeedWorldZeroEnvironment[world] adds the first computational opportunities.";

ContractIDs::usage =
    "ContractIDs[world] returns all active contract object IDs.";

ContractSummary::usage =
    "ContractSummary[world] returns compact contract statistics.";

AttemptContract::usage =
    "AttemptContract[world,inhabitantID,contractID] tests an inhabitant against a contract.";

EcologyStep::usage =
    "EcologyStep[world,maxPopulation] advances one autonomous world/environment step.";

RunEcology::usage =
    "RunEcology[world,steps,maxPopulation] runs autonomous ecological steps.";

Begin["`Private`"];

CreateContract[
    world_Association,
    id_String,
    examples_List,
    reward_Integer : 12
] :=
    Module[{record, next},

        If[
            KeyExistsQ[world["Objects"], id],
            Return[
                Failure[
                    "ObjectAlreadyExists",
                    <|"ObjectID" -> id|>
                ]
            ]
        ];

        If[
            !AllTrue[
                examples,
                MatchQ[#, {_, _}] &
            ],
            Return[
                Failure[
                    "InvalidExamples",
                    <|"Examples" -> examples|>
                ]
            ]
        ];

        record = <|
            "ObjectID" -> id,
            "Kind" -> "contract",
            "Examples" -> examples,
            "Reward" -> reward,
            "Attempts" -> 0,
            "Passes" -> 0
        |>;

        next =
            Join[
                world,
                <|
                    "Objects" ->
                        Join[
                            world["Objects"],
                            <|id -> record|>
                        ]
                |>
            ];

        TheConstruct`EmitEvent[
            next,
            "CONTRACT_CREATED",
            "world",
            <|
                "Contract" -> id,
                "ExampleCount" -> Length[examples],
                "Reward" -> reward
            |>
        ]
    ];

SeedWorldZeroEnvironment[world_Association] :=
    Module[{next = world},

        next =
            CreateContract[
                next,
                "K001",
                {
                    {0, 1},
                    {2, 3},
                    {-3, -2}
                },
                12
            ];

        next =
            CreateContract[
                next,
                "K002",
                {
                    {1, 2},
                    {3, 6},
                    {-2, -4}
                },
                12
            ];

        next =
            CreateContract[
                next,
                "K003",
                {
                    {2, 4},
                    {-3, 9},
                    {5, 25}
                },
                16
            ];

        next =
            CreateContract[
                next,
                "K004",
                {
                    {2, -2},
                    {-5, 5},
                    {0, 0}
                },
                14
            ];

        next
    ];

ContractIDs[world_Association] :=
    Keys[
        Select[
            world["Objects"],
            Lookup[#, "Kind", ""] === "contract" &
        ]
    ];

ContractSummary[world_Association] :=
    Module[{ids = ContractIDs[world]},

        Map[
            Function[id,
                With[
                    {contract = world["Objects"][id]},
                    <|
                        "ID" -> id,
                        "Attempts" ->
                            Lookup[contract, "Attempts", 0],
                        "Passes" ->
                            Lookup[contract, "Passes", 0],
                        "Reward" ->
                            Lookup[contract, "Reward", 0]
                    |>
                ]
            ],
            ids
        ]
    ];

AttemptContract[
    world_Association,
    inhabitantID_String,
    contractID_String
] :=
    Module[
        {
            contract,
            examples,
            working = world,
            outputs = {},
            run,
            passed,
            updatedContract,
            next
        },

        If[
            !KeyExistsQ[world["Objects"], contractID],
            Return[
                Failure[
                    "UnknownContract",
                    <|"Contract" -> contractID|>
                ]
            ]
        ];

        contract = world["Objects"][contractID];

        If[
            Lookup[contract, "Kind", ""] =!= "contract",
            Return[
                Failure[
                    "NotContract",
                    <|"ObjectID" -> contractID|>
                ]
            ]
        ];

        examples = contract["Examples"];

        Do[
            run =
                TheConstruct`ExecuteInhabitant[
                    working,
                    inhabitantID,
                    example[[1]]
                ];

            If[FailureQ[run], Return[run]];

            working = run["World"];
            outputs = Append[outputs, run["Output"]],
            {example, examples}
        ];

        passed =
            outputs === examples[[All, 2]];

        updatedContract =
            Join[
                contract,
                <|
                    "Attempts" ->
                        Lookup[contract, "Attempts", 0] + 1,
                    "Passes" ->
                        Lookup[contract, "Passes", 0] +
                            If[passed, 1, 0]
                |>
            ];

        working =
            Join[
                working,
                <|
                    "Objects" ->
                        Join[
                            working["Objects"],
                            <|contractID -> updatedContract|>
                        ]
                |>
            ];

        next =
            If[
                passed,
                TheConstruct`GrantResource[
                    working,
                    "Compute",
                    contract["Reward"],
                    inhabitantID
                ],
                working
            ];

        next =
            TheConstruct`EmitEvent[
                next,
                If[passed, "CONTRACT_PASSED", "CONTRACT_FAILED"],
                inhabitantID,
                <|
                    "Contract" -> contractID,
                    "Outputs" -> outputs,
                    "Expected" -> examples[[All, 2]]
                |>
            ];

        <|
            "World" -> next,
            "Passed" -> passed,
            "Outputs" -> outputs
        |>
    ];

InhabitantIDs[world_Association] :=
    Keys[
        Select[
            world["Processes"],
            Lookup[#, "Kind", ""] === "inhabitant" &
        ]
    ];

NextInhabitantID[world_Association] :=
    Module[{count},
        count = Length[InhabitantIDs[world]] + 1;
        "C" <> IntegerString[count, 10, 3]
    ];

DeterministicMutationSpec[
    world_Association,
    genome_TCProgram
] :=
    Module[
        {
            primitives,
            primitive,
            operation,
            position,
            length
        },

        primitives = TheConstruct`AvailablePrimitives[];
        length = Length[List @@ genome];

        primitive =
            primitives[
                [
                    Mod[
                        world["Tick"],
                        Length[primitives]
                    ] + 1
                ]
            ];

        operation =
            If[
                Mod[world["Tick"], 5] == 0 &&
                length > 1,
                "Replace",
                "Insert"
            ];

        position =
            If[
                operation === "Replace",
                Mod[world["Tick"], length] + 1,
                Mod[world["Tick"], length + 1] + 1
            ];

        <|
            "Operation" -> operation,
            "Primitive" -> primitive,
            "Position" -> position
        |>
    ];

EcologyStep[
    world_Association,
    maxPopulation_Integer : 30
] :=
    Module[
        {
            next,
            inhabitants,
            contracts,
            inhabitantID,
            contractID,
            attempt,
            population,
            childID,
            genome,
            spec,
            otherID,
            built
        },

        next =
            TheConstruct`AdvanceTick[
                world,
                1
            ];

        inhabitants = InhabitantIDs[next];
        contracts = ContractIDs[next];

        If[
            inhabitants === {} ||
            contracts === {},
            Return[next]
        ];

        inhabitantID =
            inhabitants[
                [
                    Mod[
                        next["Tick"] - 1,
                        Length[inhabitants]
                    ] + 1
                ]
            ];

        contractID =
            contracts[
                [
                    Mod[
                        next["Tick"] - 1,
                        Length[contracts]
                    ] + 1
                ]
            ];

        attempt =
            AttemptContract[
                next,
                inhabitantID,
                contractID
            ];

        If[
            FailureQ[attempt],
            Return[
                TheConstruct`EmitEvent[
                    next,
                    "ECOLOGY_ERROR",
                    inhabitantID,
                    <|
                        "Contract" -> contractID,
                        "Failure" ->
                            ToString[attempt, InputForm]
                    |>
                ]
            ]
        ];

        next = attempt["World"];

        population = Length[InhabitantIDs[next]];

        If[
            !TrueQ[attempt["Passed"]] &&
            population < maxPopulation,

            childID = NextInhabitantID[next];

            built =
                If[
                    Mod[next["Tick"], 4] == 0 &&
                    Length[inhabitants] >= 2,

                    otherID =
                        inhabitants[
                            [
                                Mod[
                                    next["Tick"],
                                    Length[inhabitants]
                                ] + 1
                            ]
                        ];

                    If[
                        otherID === inhabitantID,
                        otherID =
                            inhabitants[
                                [
                                    Mod[
                                        next["Tick"] + 1,
                                        Length[inhabitants]
                                    ] + 1
                                ]
                            ]
                    ];

                    TheConstruct`ComposeInhabitants[
                        next,
                        {inhabitantID, otherID},
                        childID
                    ],

                    genome =
                        next["Processes"][inhabitantID]["Genome"];

                    spec =
                        DeterministicMutationSpec[
                            next,
                            genome
                        ];

                    TheConstruct`MutateInhabitant[
                        next,
                        inhabitantID,
                        childID,
                        spec
                    ]
                ];

            If[
                !FailureQ[built],
                next = built
            ]
        ];

        TheConstruct`EmitEvent[
            next,
            "ECOLOGY_STEP",
            "world",
            <|
                "Inhabitant" -> inhabitantID,
                "Contract" -> contractID,
                "Passed" -> attempt["Passed"],
                "Population" ->
                    Length[InhabitantIDs[next]]
            |>
        ]
    ];

RunEcology[
    world_Association,
    steps_Integer,
    maxPopulation_Integer : 30
] /; steps >= 0 :=
    Nest[
        EcologyStep[#, maxPopulation] &,
        world,
        steps
    ];

End[];
EndPackage[];
