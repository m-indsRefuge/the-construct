# Inhabitant Engine

The first inhabitants are purely computational symbolic programs.

They are not language models and do not reason in natural language.

## Genome

An inhabitant genome is a Wolfram expression:

    TCProgram["Increment", "Double", ...]

The expression is executable through The Construct's primitive interpreter and
can itself be rewritten by mutation operators.

## Initial primitive vocabulary

- Identity
- Increment
- Decrement
- Double
- Negate
- Square
- Abs
- Mod10

## Current capabilities

An inhabitant can:

- execute its symbolic genome
- consume world compute
- produce observable output
- generate a mutated descendant
- inherit lineage
- compose with other inhabitants into a larger program

This is the first version of computation building computation.

The next subsystem is Environment & Contracts.
