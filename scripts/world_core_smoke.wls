root = DirectoryName[DirectoryName[$InputFileName]];
Get[FileNameJoin[{root,"construct","wolfram","TheConstruct.wl"}]];

world=TheConstruct`CreateWorld[7];
world=TheConstruct`RegisterProcess[world,"WORLD-KERNEL","kernel"];
world=TheConstruct`AdvanceTick[world,3];
world=TheConstruct`SpendResource[world,"Compute",25,"WORLD-KERNEL"];

overdraft=TheConstruct`SpendResource[world,"Compute",5000,"WORLD-KERNEL"];

checks={
 TheConstruct`ValidWorldQ[world],
 world["Tick"]===3,
 world["Resources"]["Compute"]===975,
 Length[world["Processes"]]===1,
 Lookup[world["Events"],"EventID"]===Range[Length[world["Events"]]],
 MatchQ[overdraft,_Failure]
};

Print[""];
Print["========================================"];
Print["       THE CONSTRUCT : WORLD CORE"];
Print["========================================"];
Print[""];
Print["SUMMARY=",InputForm[TheConstruct`WorldSummary[world]]];
Print["CHECKS=",checks];

If[And@@checks,
 Print["WORLD_CORE_GREEN"]; Exit[0],
 Print["WORLD_CORE_FAILED"]; Exit[1]
];
