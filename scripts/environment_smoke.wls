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

world = TheConstruct`CreateWorld[21];

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

world =
    TheConstruct`CreateInhabitant[
        world,
        "C003",
        TheConstruct`TCProgram["Identity"]
    ];

world =
    TheConstruct`SeedWorldZeroEnvironment[
        world
    ];

world =
    TheConstruct`RunEcology[
        world,
        16,
        20
    ];

population =
    TheConstruct`PopulationSummary[world];

contracts =
    TheConstruct`ContractSummary[world];

eventTypes =
    Lookup[
        world["Events"],
        "Type"
    ];

checks = {
    world["Tick"] === 16,
    Length[population] > 3,
    Total[Lookup[contracts, "Passes"]] >= 2,
    MemberQ[eventTypes, "CONTRACT_PASSED"],
    MemberQ[eventTypes, "CONTRACT_FAILED"],
    MemberQ[eventTypes, "GENOME_MUTATED"],
    MemberQ[eventTypes, "INHABITANTS_COMPOSED"],
    TheConstruct`ValidWorldQ[world]
};

Print[""];
Print["============================================"];
Print["        THE CONSTRUCT : WORLD ZERO"];
Print["============================================"];
Print[""];

Print[
    "TICK=",
    world["Tick"],
    "  POPULATION=",
    Length[population],
    "  COMPUTE=",
    world["Resources"]["Compute"]
];

Print[""];
Print["CONTRACTS"];

Scan[
    Print[InputForm[#]] &,
    contracts
];

Print[""];
Print["POPULATION"];

Scan[
    Print[InputForm[#]] &,
    population
];

Print[""];
Print["RECENT WORLD EVENTS"];

Scan[
    Print[
        #["EventID"],
        "  ",
        #["Type"],
        "  ",
        #["Actor"]
    ] &,
    Take[world["Events"], -20]
];

Print[""];
Print["CHECKS=", checks];

If[
    And @@ checks,
    Print["ENVIRONMENT_GREEN"];
    Exit[0],
    Print["ENVIRONMENT_FAILED"];
    Exit[1]
];
