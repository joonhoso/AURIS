# esa-space-protocols

A Haskell library for handling space protocols from the European Space Ageny (ESA). 

Currently under heavy construction and creation. 

## Current Features ##

 * CLTU encoding/decoding with TC randomization
 * TC Transfer Frame encoding/decoding
 * TC Segment encoding/decoding and segmenting a PUS Packet into TC Segments. Basic functions for assembling a packet out of segments is also available
 
Current work focuses on the command link. Goal is to have a conduit based pipeline of command encoding flowing from a command request -> TC packet -> PUS packet -> segments -> COP-1 -> TC transfer frames -> CLTU -> Transfer Protocol. Parts of these are already present, but currently there is no complete pipeline. Some code skeletons are available to lay out the types used (e.g. a module defining the data types and then a encoder which contains a conduit to transform the data type to the next layer).

Encoding from TC-Transfer Frame and sending via NCTRS protocol already works.
 
 ## Building ##
 
 ### Building with stack ###
 
 You can use `stack` to build the project. To enable the llvm build, specify:
  * --flag esa-space-protocols:llvm
 
 `stack test` builds and runs the tests, `stack bench` builds and runs the benchmarks.
 
 
 ### Building with Cabal ###
 
 Currently, `cabal new-build` is used. It accepts the following flags:
  * `-f llvm`: build via LLVM

There are also unit tests available (with `cabal new-configure --enable-tests`) and 
also benchmarks (with `cabal new-configure --enable-benchmarks`).

Documentation can be built as usual with `cabal new-haddock`, though it is currently only exhaustive for CLTUs, Randomizer and the Config.

### Build within docker ###

 Prepare a docker image with `make docker-build`. It sets up a devlopment user "dev"
 which has the same UID and GID as the user at the docker host.
 This directory is mounted in the home directory of dev, so build artifacts 
 are persistent, editable and removable afterwards from the outside.

 Start the docker container with `make docker-run`.
 If within AUK and internet connection is necessary (e.g. for cabal update),
 source etc/setProxy.sh.
 
## TODO ##

First, get all working.
 * Commanding independent of spacecraft definitions (MIB, CDM)
 * Telemetry independent of spacecraft definitions, so the basic layers (packets)
 * Probably another library for MIB handling will be needed. Also, a general internal model should be present so that alternative representations (e.g. EGS-CCs CDM) can be used too.
 * Adding the MIB/data model to be able to send specific commands and extract TM (parameters)
 * Play around with parallel TM extraction and how to distribute parameters
 * Definition of interfaces
 * Some user interfaces
 
That's enough for the next weeks.
