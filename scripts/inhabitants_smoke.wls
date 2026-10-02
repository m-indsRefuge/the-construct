root = DirectoryName[DirectoryName[$InputFileName]];

Get[
    FileNameJoin[
        {
            root,
            "construct",
            "wolfram",
            "TheConstruct.wl"
        }
    ]
];

world = TheConstruct`CreateWorld[11];

world =
    TheConstruct`CreateInhabitant[
        world,
        "C001",
        TheConstruct`TCProgram["Increment"]
    ];

world =
    TheConstruct`CreateInhabitant[
        world,
        "C002",
        TheConstruct`TCProgram["Double"]
    ];

run1 =
    TheConstruct`ExecuteInhabitant[
        world,
        "C001",
        3
    ];

world = run1["World"];
output1 = run1["Output"];

world =
    TheConstruct`MutateInhabitant[
        world,
        "C001",
        "C003",
        <|
            "Operation" -> "Insert",
            "Primitive" -> "Double",
            "Position" -> 2
        |>
    ];

run3 =
    TheConstruct`ExecuteInhabitant[
        world,
        "C003",
        3
    ];

world = run3["World"];
output3 = run3["Output"];

world =
    TheConstruct`ComposeInhabitants[
        world,
        {"C002", "C003"},
        "C004"
    ];

run4 =
    TheConstruct`ExecuteInhabitant[
        world,
        "C004",
        3
    ];

world = run4["World"];
output4 = run4["Output"];

events = Lookup[world["Events"], "Type"];

checks = {
    output1 === 4,
    output3 === 8,
    output4 === 14,
    Length[TheConstruct`PopulationSummary[world]] === 4,
    world["Processes"]["C003"]["Generation"] === 1,
    world["Processes"]["C004"]["Generation"] === 2,
    MemberQ[events, "GENOME_MUTATED"],
    MemberQ[events, "INHABITANTS_COMPOSED"],
    TheConstruct`ValidWorldQ[world]
};

Print[""];
Print["============================================"];
Print["     THE CONSTRUCT : FIRST INHABITANTS"];
Print["============================================"];
Print[""];

Print["PRIMITIVES=", TheConstruct`AvailablePrimitives[]];
Print[""];

Print["C001 INPUT 3 -> ", output1];
Print["C003 MUTANT INPUT 3 -> ", output3];
Print["C004 COMPOSITE INPUT 3 -> ", output4];
Print[""];

Print["POPULATION"];

Scan[
    Print[InputForm[#]] &,
    TheConstruct`PopulationSummary[world]
];

Print[""];
Print["RECENT EVENTS"];

Scan[
    Print[
        #["EventID"],
        "  ",
        #["Type"],
        "  ",
        #["Actor"]
    ] &,
    Take[world["Events"], -10]
];

Print[""];
Print["CHECKS=", checks];
Print[
    "COMPUTE_REMAINING=",
    world["Resources"]["Compute"]
];

If[
    And @@ checks,
    Print["INHABITANT_ENGINE_GREEN"];
    Exit[0],
    Print["INHABITANT_ENGINE_FAILED"];
    Exit[1]
];
