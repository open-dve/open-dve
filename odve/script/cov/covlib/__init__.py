"""covlib - the library behind script/cov/covgen.py (doc/fcov-plan.md 5.2).

model     the coverage model (groups, points, bins, crosses)
filelist  reader for the -f filelists the simulators consume
cgparse   extraction of `ifdef ODVE_COV_NATIVE blocks and the covergroup
          subset parser that turns them into the model
gen       generator: model -> odve_cov_gen.svh, generated classes, covmap.json

Standard library only, Python 3.9+."""
