(* ::Package:: *)

BeginPackage["TheConstruct`"];

CreateWorld::usage = "CreateWorld[seed] creates a new Construct world.";
EmitEvent::usage = "EmitEvent[world,type,actor,data] appends an event.";
AdvanceTick::usage = "AdvanceTick[world,n] advances the world clock.";
SpendResource::usage = "SpendResource[world,resource,amount,actor] spends a resource.";
GrantResource::usage = "GrantResource[world,resource,amount,actor] grants a resource.";
RegisterProcess::usage = "RegisterProcess[world,id,kind] registers a process.";
WorldSummary::usage = "WorldSummary[world] returns a compact world summary.";
ValidWorldQ::usage = "ValidWorldQ[world] validates World Core invariants.";

Begin["`Private`"];

EmitEvent[world_Association,type_String,actor_String:"world",data_Association:<||>] := Module[{event},
 event=<|"EventID"->world["NextEventID"],"Tick"->world["Tick"],"Type"->type,"Actor"->actor,"Data"->data|>;
 Join[world,<|"Events"->Append[world["Events"],event],"NextEventID"->world["NextEventID"]+1|>]
];

CreateWorld[seed_Integer:1] := EmitEvent[
 <|"WorldID"->("world-"<>ToString[seed]),"Seed"->seed,"Tick"->0,"Status"->"running",
   "Resources"-><|"Compute"->1000,"Memory"->256|>,"Processes"-><||>,"Objects"-><||>,
   "Events"->{}, "NextEventID"->1|>,
 "WORLD_CREATED","world",<|"Seed"->seed|>
];

AdvanceTick[world_Association,count_Integer:1] /; count>0 := Nest[
 Function[current,With[{next=Join[current,<|"Tick"->current["Tick"]+1|>]},
   EmitEvent[next,"TICK","world",<|"Tick"->next["Tick"]|>]]],
 world,count
];

SpendResource[world_Association,resource_String,amount_Integer?NonNegative,actor_String:"world"] := Module[
 {r=world["Resources"],available,next},
 If[!KeyExistsQ[r,resource],Return[Failure["UnknownResource",<|"Resource"->resource|>]]];
 available=r[resource];
 If[amount>available,Return[Failure["InsufficientResource",<|"Resource"->resource,"Requested"->amount,"Available"->available|>]]];
 next=Join[world,<|"Resources"->Join[r,<|resource->available-amount|>]|>];
 EmitEvent[next,"RESOURCE_SPENT",actor,<|"Resource"->resource,"Amount"->amount|>]
];

GrantResource[world_Association,resource_String,amount_Integer?NonNegative,actor_String:"world"] := Module[
 {r=world["Resources"],available,next},
 If[!KeyExistsQ[r,resource],Return[Failure["UnknownResource",<|"Resource"->resource|>]]];
 available=r[resource];
 next=Join[world,<|"Resources"->Join[r,<|resource->available+amount|>]|>];
 EmitEvent[next,"RESOURCE_GRANTED",actor,<|"Resource"->resource,"Amount"->amount|>]
];

RegisterProcess[world_Association,processID_String,kind_String:"process"] := Module[
 {p=world["Processes"],record,next},
 If[KeyExistsQ[p,processID],Return[Failure["ProcessAlreadyExists",<|"ProcessID"->processID|>]]];
 record=<|"ProcessID"->processID,"Kind"->kind,"CreatedTick"->world["Tick"],"Status"->"active"|>;
 next=Join[world,<|"Processes"->Join[p,<|processID->record|>]|>];
 EmitEvent[next,"PROCESS_REGISTERED",processID,<|"Kind"->kind|>]
];

WorldSummary[world_Association] := <|
 "WorldID"->world["WorldID"],"Tick"->world["Tick"],"Status"->world["Status"],
 "Compute"->world["Resources"]["Compute"],"Memory"->world["Resources"]["Memory"],
 "ProcessCount"->Length[world["Processes"]],"ObjectCount"->Length[world["Objects"]],
 "EventCount"->Length[world["Events"]]
|>;

ValidWorldQ[world_Association] := And[
 KeyExistsQ[world,"WorldID"],IntegerQ[world["Tick"]],world["Tick"]>=0,
 AssociationQ[world["Resources"]],KeyExistsQ[world["Resources"],"Compute"],KeyExistsQ[world["Resources"],"Memory"],
 world["Resources"]["Compute"]>=0,world["Resources"]["Memory"]>=0,
 AssociationQ[world["Processes"]],AssociationQ[world["Objects"]],ListQ[world["Events"]],
 world["NextEventID"]===Length[world["Events"]]+1
];

End[];
EndPackage[];
