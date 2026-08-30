@echo off
cd /d "%~dp0"
copy /b RangeDay2.zip.part00+RangeDay2.zip.part01+RangeDay2.zip.part02+RangeDay2.zip.part03+RangeDay2.zip.part04+RangeDay2.zip.part05+RangeDay2.zip.part06+RangeDay2.zip.part07 RangeDay2.zip
tar -xf RangeDay2.zip
del RangeDay2.zip
echo.
echo Done - RangeDay2.exe is ready in this folder. Double-click it to play.
pause
