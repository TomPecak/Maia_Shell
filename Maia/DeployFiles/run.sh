#!/bin/bash

# solve long gtk+ applications startup
export GTK_USE_PORTAL=0
export LD_LIBRARY_PATH=/opt/Maia/Maia_0.1.0/lib:$LD_LIBRARY_PATH

/opt/Maia/Maia_0.1.0/bin/appMaiaServer
