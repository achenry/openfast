% make sure the OpenFAST directory where the FAST_SFunc.mex* file is located
% is in the MATLAB path (also make sure any other OpenFAST library files that
% are needed are on the MATLAB path)
%    (relative path names are not recommended in addpath()):
% addpath('../../../build/bin'); % install location for Windows Visual Studio builds
addpath(genpath('../../../install')); % cmake default install location

% these variables are defined in the OpenLoop model's FAST_SFunc block:
% FAST_InputFileName = '../../../reg_tests/r-test/glue-codes/openfast/AOC_WSt/AOC_WSt.fst';
TMax               = 60; % seconds
DT = 1;
FAST_InputFileName = '/Users/aoifework/Documents/dev/WEIS/ROSCO/Test_Cases/5MW_Land_Simulink/5MW_Land_Simulink.fst';

sim('OpenLoop.mdl',[0,TMax]);
