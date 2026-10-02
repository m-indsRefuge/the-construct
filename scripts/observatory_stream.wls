(* Wolfram-authoritative World Zero JSONL exporter for the Observatory. *)
root = DirectoryName[DirectoryName[$InputFileName]];
$Messages = {$StandardErrorStream};
Get[FileNameJoin[{root, "construct", "wolfram", "TheConstruct.wl"}]];

parseScriptArguments[arguments_List] := Module[
  {options = <||>, index = 1, token, name, value, separator},
  While[index <= Length[arguments],
    token = arguments[[index]];
    If[StringStartsQ[token, "--"],
      separator = StringPosition[token, "=", 1];
      If[separator === {},
        name = StringDrop[token, 2];
        value = "";
        If[index < Length[arguments] && !StringStartsQ[arguments[[index + 1]], "--"],
          index++;
          value = arguments[[index]]
        ],
        name = If[separator[[1, 1]] <= 3, "", StringTake[token, {3, separator[[1, 1]] - 1}]];
        value = StringDrop[token, separator[[1, 1]]]
      ];
      If[name =!= "", AssociateTo[options, name -> value]]
    ];
    index++
  ];
  options
];
scriptArguments = If[Length[$ScriptCommandLine] > 0, Rest[$ScriptCommandLine], {}];
scriptOptions = parseScriptArguments[scriptArguments];
argument[name_, default_] := Lookup[scriptOptions, name, default];
argumentError[message_] := (
  WriteString[$StandardErrorStream, "Observatory: " <> message <> ".\n"];
  Exit[2]
);
integerArgument[name_, default_, minimum_] := Module[{value, parsed},
  If[!KeyExistsQ[scriptOptions, name], Return[default]];
  value = scriptOptions[name];
  If[!StringMatchQ[value, RegularExpression["[+-]?[0-9]+"]],
    argumentError["--" <> name <> " must be an integer"]
  ];
  parsed = Quiet[Check[ToExpression[value], $Failed]];
  If[!IntegerQ[parsed] || parsed < minimum,
    argumentError["--" <> name <> " is outside the allowed range"]
  ];
  parsed
];
numericArgument[name_, default_, minimum_] := Module[{value, parsed},
  If[!KeyExistsQ[scriptOptions, name], Return[default]];
  value = scriptOptions[name];
  If[!StringMatchQ[value, RegularExpression["[+-]?[0-9]+(\\.[0-9]+)?"]],
    argumentError["--" <> name <> " must be numeric"]
  ];
  parsed = Quiet[Check[N[ToExpression[value]], $Failed]];
  If[!NumberQ[parsed] || parsed < minimum,
    argumentError["--" <> name <> " is outside the allowed range"]
  ];
  parsed
];
seed = integerArgument["seed", 42, -Infinity];
delay = numericArgument["delay", 0.5, 0];
steps = integerArgument["steps", 0, 0];
maxPopulation = integerArgument["max-population", 30, 1];
controlFile = argument["control-file", ""];
If[!NumericQ[delay] || delay < 0, delay = 0.5];
If[steps < 0, steps = 0];
If[maxPopulation < 1, maxPopulation = 30];

jsonValue[value_] := Which[
  MissingQ[value], Null,
  IntegerQ[value] || StringQ[value] || TrueQ[value === True] || TrueQ[value === False], value,
  ListQ[value], jsonValue /@ value,
  AssociationQ[value], Association @ KeyValueMap[#1 -> jsonValue[#2] &, value],
  NumberQ[value], N[value],
  True, ToString[value, InputForm]
];
frame[world_] := Module[{population, contracts, events},
  population = Function[s, <|"id" -> s["ID"], "generation" -> s["Generation"],
    "parents" -> s["Parents"], "genome" -> s["Genome"],
    "executions" -> s["Executions"], "last_output" -> jsonValue[s["LastOutput"]]|>] /@
    TheConstruct`PopulationSummary[world];
  contracts = Function[s, <|"id" -> s["ID"], "attempts" -> s["Attempts"],
    "passes" -> s["Passes"], "reward" -> s["Reward"]|>] /@
    TheConstruct`ContractSummary[world];
  events = Function[e, <|"id" -> e["EventID"], "tick" -> e["Tick"], "type" -> e["Type"],
    "actor" -> e["Actor"], "data" -> jsonValue[e["Data"]]|>] /@
    Take[world["Events"], -Min[24, Length[world["Events"]]]];
  <|"tick" -> world["Tick"], "status" -> world["Status"],
    "compute" -> world["Resources"]["Compute"], "memory" -> world["Resources"]["Memory"],
    "population_count" -> Length[population], "object_count" -> Length[world["Objects"]],
    "population" -> population, "contracts" -> contracts, "events" -> events|>
];
emit[world_] := Module[{encoded},
  encoded = Quiet[Check[ExportString[frame[world], "JSON", "Compact" -> True], $Failed]];
  If[!StringQ[encoded] || encoded === "$Failed",
    WriteString[$StandardErrorStream, "Observatory: failed to export a JSON frame.\n"];
    Exit[1]
  ];
  WriteString[$Output, encoded, "\n"];
  Flush[$Output]
];
readDelay[] := Module[{value},
  If[controlFile === "" || !FileExistsQ[controlFile], Return[delay]];
  value = Quiet[Check[ToExpression[Import[controlFile, "Text"]], delay]];
  If[NumericQ[value] && value >= 0, value, delay]
];
world = TheConstruct`CreateWorld[seed];
world = TheConstruct`CreateInhabitant[world, "C001", TheConstruct`TCProgram["Increment"]];
world = TheConstruct`CreateInhabitant[world, "C002", TheConstruct`TCProgram["Double"]];
world = TheConstruct`CreateInhabitant[world, "C003", TheConstruct`TCProgram["Identity"]];
world = TheConstruct`SeedWorldZeroEnvironment[world];
emit[world];
tick = 0;
While[steps == 0 || tick < steps,
  currentDelay = readDelay[];
  If[currentDelay > 0, Pause[currentDelay]];
  world = TheConstruct`EcologyStep[world, maxPopulation];
  tick++;
  emit[world];
];






