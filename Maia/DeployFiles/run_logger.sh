#!/bin/bash

export LD_LIBRARY_PATH=/opt/Maia/Maia_0.1.0/lib:$LD_LIBRARY_PATH

export MAIA_LOG_PORT=9

/opt/Maia/Maia_0.1.0/bin/appLogger
