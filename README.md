# A framework for smart contract verification in Coq

The development comes in two flavors:

* [theories/Monomorphic](theories/Monomorphic) - contains a monomorhic fragment of Oak with WIP soundness theorem proof.
* [theories/Polymorphic](theories/Polymorphic) - contains more featureful translation supporting polymorphism. It also features translation of parameterised inductive types.

## Examples

To show how to use the framework, we develop the following examples:

* Simple demonstration can be found in [theories/Polymorphic/Demo.v](theories/Polymorphic/Demo.v)
* Verification of a crowdfunding contract: [theories/Examples/ExampleContracts.v](theories/Examples/ExampleContracts.v)
* A demonstration how one can verify library code: [theories/Examples/OakMap.v](theories/Examples/OakMap.v). This example shows a simple finite map implementation in our deep embedding of Oak and how one can show that the corresponding shallow embedding is equivalent to the Coq's standard library functions.

## Documentation

The documentation generated using Coqdoc and [coqdocjs](https://github.com/tebbi/coqdocjs) is located [here](https://annenkov.github.io/FMBC19-artifact/toc.html).
