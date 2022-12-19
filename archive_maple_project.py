#!/usr/bin/python3

import sys
import os

# dir := FileTools:-JoinPath([currentdir(), "/<libname>.mla"]);
# march('create', dir);
# read "<filename>.mpl";
# savelib('<modulename>', dir);

if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(1)

    libname = str(sys.argv[1])
    filename = str(sys.argv[2])
    modulename = str(sys.argv[3])

    f = open("installation_script.mpl", "w");
    f.write(f"dir := FileTools:-JoinPath([currentdir(), \"/{libname}.mla\"]);\n")
    f.write(f"march('create', dir);\n")
    f.write(f"read \"{filename}.mpl\";\n")
    f.write(f"savelib('{modulename}', dir);\n")
    f.close()

    os.system(f"rm -rf {libname}.mla")
    os.system('maple installation_script.mpl')
    os.system('rm installation_script.mpl')
