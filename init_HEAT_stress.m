% init_HEAT.m
%
% Intialise the HEAT tool box. Sets up directory paths to core climate
% input data and adds any necessary paths.

% Find which machine is being used
root_dir = pwd;

% Running AKA's VM or local machine
if length(root_dir) >= 14
    if strcmp(root_dir(1:12),'/home/alanka')
        Tempdirin = '/home/alanka/Downloads/testing/';
        Humdirin = '/home/alanka/Downloads/testing/';
        Climatedirout = '/home/alanka/testing/';
        
    else
        % Set data directories
        Inputdir = '/data/inputs/';
        Tempdirin = '/Volumes/DataDrive/UKCP18/12km/tasmax/run04/';
        %     Tempdirin = '/Volumes/DataDrive/UKCP18/12km/tas/run04/';
        %     Tempdirin = '/Volumes/DataDrive/UKCP18/12km/tasmin/run04/';
        TempAltdirin = '/Volumes/DataDrive/UKCP18/12km/tas/run04/';
        %     Humdirin = '/Volumes/DataDrive/UKCP18/12km/hurs/run04/';
        Humdirin = '/Volumes/DataDrive/UKCP18/12km/huss/run04/';
        Pressuredirin = '/Volumes/DataDrive/UKCP18/12km/psl/run04/';
        Htdirin = '/Volumes/DataDrive/UKCP18/Height/';
        
        Climatedirout = '/Volumes/DataDrive/HEAToutput/DerivedData/';
    end
    
    % Otherwise, assume running on DAFNI (in a Docker container)
else
    % Set data directory
    Inputdir = '/data/inputs/';
    Tempdirin = '/data/inputs/Temperature/';
    TempAltdirin = '/data/inputs/Temperature_alt/';
    Humdirin = '/data/inputs/Humidity/';
    Pressuredirin = '/data/inputs/Pressure/';
    Htdirin = '/data/inputs/Height/';
    
    Climatedirout = '/data/outputs/Climate/';
    
    % Note: in this case, 'addpath' should have been done before building
    % the Matlab executable and Docker file, by running add_paths.m.
    
end
