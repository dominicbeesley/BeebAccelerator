from vunit.verilog import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv()

# Create library 'lib'
lib = vu.add_library("lib")

# Add all files ending in .vhd in current working directory to library
lib.add_source_files("./beeb_accelerator_vunit_tb.sv")
lib.add_source_files("./dcm.v")
lib.add_source_files("../src/*.v")

tb = lib.test_bench("beeb_accelerator_tb")

tb.set_parameter("ROOT","../../../src/")

# Run vunit function
vu.main()