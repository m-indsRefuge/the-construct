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

world = TheConstruct`CreateWorld[42];

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

Do[
    world =
        TheConstruct`EcologyStep[
            world,
            25
        ];

    Print[
        "tick=",
        world["Tick"],
        "  population=",
        Length[TheConstruct`PopulationSummary[world]],
        "  compute=",
        world["Resources"]["Compute"]
    ],
    {24}
];

Print[""];
Print["FINAL POPULATION"];

Scan[
    Print[InputForm[#]] &,
    TheConstruct`PopulationSummary[world]
];

Print[""];
Print["CONTRACT RESULTS"];

Scan[
    Print[InputForm[#]] &,
    TheConstruct`ContractSummary[world]
];
