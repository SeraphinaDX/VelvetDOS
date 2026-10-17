@ECHO OFF
REM VelvetDOS 0.12.0 DOS batch interpreter regression
ECHO VelvetDOS 0.12.0 batch started
SET BATCHOK=YES
PATH A:\
ENVCHK
STATUS
SET BATCHOK=
ECHO Batch finished; BATCHOK deleted
PSPTEST hello MiXeD 123
STATUS
