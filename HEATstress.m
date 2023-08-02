function [] = HEATstress(inputs)
% HEAT-stress v.2.0
%
% Run the OpenCLIM Heat Extremes Analysis Toolbox (HEAT) for calculating
% heat stress metrics. Climate data in netCDF format is converted to one of
% the following heat stress metrics:
%  1) Simplified Wet Bulb Globe Temperature
%  2) Humidex
%  3) Apparent Temperature
%  4) Temperature Humidity Index
% 
% 1-3 are calculated following the equations of Zhao et al. 2015.
% 4 is calculated following the equation of Dunn et al. 2014.
% 
% All metrics require a temperature and humidity input. All equations for
% 1-4 require daily mean vapour pressure as the humidity measure, however
% it is possible to provide other humidity measures which are then
% converted to vapour pressure. Alternative possible humidity measures are:
%  1) Dew point temperature
%  2) Relative humidity
%  3) Specific humidity
% 
% No additional climate variables are required for converting dew point
% temperature to vapour pressure. Conversion of relative humidity to vapour
% pressure requires daily mean temperature to be provided. Conversion of
% specific humidity requires daily mean temperature and daily mean surface
% pressure to be provided. Alternatively, sea level pressure can be
% provided along with a file showing surface height at each grid cell
% (named ht.csv) and the conversion of sea level pressure to surface
% pressure will be carried out.
% 
% This assumes there is temporal and spatial consistency between all input
% climate variables and, if required, the surface height field (ht.csv) is
% on the same spatial grid. 
% 
% It is assumed that the netCDF inputs use the same variable naming
% convention as UKCP18. If not (e.g. instead of relative humidity being
% called 'hurs',' it is called 'RH'), then the variable name must be
% provided. Additionally, heat stress metrics can be calculated for the
% daily maximum by providing a daily maximum temperature netCDF, however in
% this case if vapour pressure is to be calculated, daily mean temperature
% must also be provided in the second temperature data slot.
% 
% The output will be saved in netCDF format concatenating all time steps
% together. The output file name can be adjusted by providing an experiment
% name, taking the format ExptName_HeatStressMetric_StartDate-EndDate.nc.
% Additionally, the input choices will be saved as inputs.mat so the result
% can be reproduced in future if necessary. 
% 
% 'inputs' is an optional structure for running locally.
%
% Coded by A.T. Kennedy-Asser, University of Bristol, 2023.
% Contact: alan.kennedy@bristol.ac.uk
%

%% Initialise
disp('Running HEAT-stress v.2.0')
disp('-----')

% Set directory paths
init_HEAT_stress

% Record start time
startt = now;


%% Update fields if Environment Variables are provided
% Do this if running in Docker container. If running locally, an inputs
% file can be provided for testing.
if ~exist('inputs','var')
    
    disp('Updating inputs with environment variables')
    
    % Read the compulsory environment variables
    env_metric = getenv('METRIC');
    env_maxmeanmin = getenv('MAXMEANMIN');
    env_humidity = getenv('HUMIDITY');
    
    if ~isempty(env_metric)
        disp(['Calculating for ',string(env_metric)])
        inputs.Metric = string(env_metric);
    end
    
    if ~isempty(env_maxmeanmin) % 'mean', 'max', 'min'
        disp(['Using temperature data for daily ',string(env_maxmeanmin)])
        inputs.MaxMeanMin = string(env_maxmeanmin);
    end
    
    if ~isempty(env_humidity)
        disp(['Humidity metric is ',string(env_humidity)])
        inputs.Humidity = string(env_humidity);
    end
    
    % These are optional to set variable names in netCDFs
    env_humname = getenv('HUMIDITYNAME');
    env_tas1name = getenv('TEMPNAME');
    env_tas2name = getenv('TEMPALTNAME');
    env_pname = getenv('PRESSURENAME');
    env_expname = getenv('EXPNAME');
    env_xname = getenv('XNAME');
    env_yname = getenv('YNAME');
    env_datename = getenv('DATENAME');
    env_timename = getenv('TIMENAME');
    env_ukcp18 = getenv('UKCP18');

    
    if ~isempty(env_humname)
        inputs.HumidityName = string(env_humname);
    else
        inputs.HumidityName = string(env_humidity);
    end
    
    if ~isempty(env_tas1name)
        inputs.TempName = string(env_tas1name);
    else
        if strcmp(inputs.MaxMeanMin,'max')
            inputs.TempName = 'tasmax'; % Default
        elseif strcmp(inputs.MaxMeanMin,'min')
            inputs.TempName = 'tasmin'; % Default
        else
            inputs.TempName = 'tas'; % Default
        end
    end
    
    if ~isempty(env_tas2name)
        inputs.TempAltName = string(env_tas2name);
    else
        inputs.TempAltName = 'tas'; % Default
    end
    
    if ~isempty(env_pname)
        inputs.PresName = string(env_pname);
    else
        inputs.PresName = 'psl'; % Default
    end
    
    if ~isempty(env_expname)
        inputs.ExptName = string(env_expname)
    end
    
    % General info for loading netCDF dimensions
    if ~isempty(env_xname)
        xname = char(env_xname);
    else
        xname = 'projection_x_coordinate'; % Default for UKCP18
    end
    
    if ~isempty(env_yname)
        yname = char(env_yname);
    else
        yname = 'projection_y_coordinate'; % Default for UKCP18
    end
    
    if ~isempty(env_timename)
        timename = char(env_timename);
    else
        timename = 'time'; % Default for UKCP18
    end
    
    if ~isempty(env_datename)
        datename = string(env_datename);
    else
        datename = 'yyyymmdd'; % Default for UKCP18
    end
    
    
    if ~isempty(env_ukcp18)
         if strcmp(string(env_ukcp18),'UKCP18')
            inputs.UKCP18 = 1; % Default
         elseif strcmp(string(env_ukcp18),'Other')
            inputs.UKCP18 = 0;
         end
        % To do: add option for ERA5?
    end
end


%% Set up output directory
if ~isfield(inputs,'ExptName')
    inputs.ExptName = 'Default';
end

% If running locally, create a sub-folder for output with ExptName
if length(root_dir) >= 14
    outdir = [char(Climatedirout),char(inputs.ExptName)]
else % If running in Docker, save direct to output directory
    outdir = Climatedirout
end
        
% Next, check if output directory already exists
if ~exist(outdir,'dir')
    % Create output directory
    mkdir(outdir)
end

% Save input files for future reference
save([outdir,'/inputs.mat'],'inputs')


%% Calculate/load vapour pressure
if strcmp(inputs.Humidity,'VP')
    disp('Vapour pressure provided to model. Load this...')
    
    % Find humidity (Vapour Pressure) files:
    froot = Humdirin; % Take the file name...
    files = dir([froot '*.nc']); % Then check if any files exist with this root
    
    if ~isempty(files)
        for f = 1:length(files)
            file = [files(f).folder,'/',files(f).name];
            
            % Load humidity file
            if f == 1
                VP = double(ncread(file,inputs.HumidityName));
            else
                VP = cat(3,VP,double(ncread(file,inputs.HumidityName)));
            end
            
        end
    end
    
elseif strcmp(inputs.Humidity,'DPT') % This is provided by ERA5
    disp('Dew point temperature provided to model. Load this and convert to vapour pressure...')
    
    % Find humidity (dew point temperature) files:
    froot = Humdirin; % Take the file name...
    files = dir([froot '*.nc']); % Then check if any files exist with this root
    
    if ~isempty(files)
        for f = 1:length(files)
            file = [files(f).folder,'/',files(f).name];
            
            % Load temperature for the correct region and concatenate through time if necessary
            if f == 1
                VP = DPT2VP(double(ncread(file,inputs.HumidityName)));
            else
                VP = cat(3,VP,DPT2VP(double(ncread(file,inputs.HumidityName))));
            end
            
        end
    end
    
elseif strcmp(inputs.Humidity,'RH')
    disp('Relative humidity provided to model. Load this and convert to vapour pressure...')
    
    % Check if temperature variable is daily mean, if not load mean from
    % Temperature_alt
    if strcmp(inputs.MaxMeanMin,'mean')
       tempmeandir = Tempdirin;
    else
       tempmeandir = TempAltdirin; 
    end
    
    % Find humidity (relative humidity) files, plus daily mean temperature for conversion to vapour pressure:
    froot = Humdirin; % Take the file name...
    files = dir([froot '*.nc']); % Then check if any files exist with this root
    tfiles = dir([tempmeandir '*.nc']); % Then check if any temperature files exist with this root

    if ~isempty(files)
        for f = 1:length(files)
            file = [files(f).folder,'/',files(f).name];
            tfile = [tfiles(f).folder,'/',tfiles(f).name];
            
            % Load temperature for the correct region and concatenate through time if necessary
            if f == 1
                RH = double(ncread(file,inputs.HumidityName));
                t = double(ncread(tfile,inputs.TempAltName));
                VP = hurs2VP(RH,t);
            else
                RH = double(ncread(file,inputs.HumidityName));
                t = double(ncread(tfile,inputs.TempAltName));
                VP = cat(3,VP,hurs2VP(RH,t));
            end
            
        end
    end
    
elseif strcmp(inputs.Humidity,'SH')
    disp('Specific humidity provided to model. Load this and convert to vapour pressure...')

    % Check if temperature variable is daily mean, if not load mean from
    % Temperature_alt
    if strcmp(inputs.MaxMeanMin,'mean')
       tempmeandir = Tempdirin;
    else
       tempmeandir = TempAltdirin; 
    end
    
    % Find humidity (specific humidity) files, plus daily mean temperature and pressure for conversion to vapour pressure:
    froot = Humdirin; % Take the file name...
    files = dir([froot '*.nc']); % Then check if any files exist with this root
    tfiles = dir([tempmeandir '*.nc']); % Then check if any files exist with this root
    pfiles = dir([Pressuredirin '*.nc']); % Then check if any files exist with this root

    if ~isempty(files)
        for f = 1:length(files)
            file = [files(f).folder,'/',files(f).name];
            tfile = [tfiles(f).folder,'/',tfiles(f).name];
            pfile = [pfiles(f).folder,'/',pfiles(f).name];
            
            % Load temperature for the correct region and concatenate through time if necessary
            if f == 1
                SH = double(ncread(file,inputs.HumidityName));
                p = double(ncread(pfile,inputs.PresName));
                % If pressure is in Pa, convert to hPa
                if nanmean(nanmean(nanmean(p)))>2000 
                    p = p/100;
                end
                % If pressure is sea level pressure, it must be converted
                % to surface pressure, requiring surface height to be
                % loaded
                if strcmp(inputs.PresName,'psl')
                    ht = csvread([Htdirin,'ht.csv']);
                    t = double(ncread(tfile,inputs.TempAltName));
                    p = p_surf(p,t,ht); % Convert to surface pressure
                end
                VP = VapourPressure(SH,p);
            else
                SH = double(ncread(file,inputs.HumidityName));
                p = double(ncread(pfile,inputs.PresName));
                % If pressure is in Pa, convert to hPa
                if nanmean(nanmean(nanmean(p)))>2000 
                    p = p/100;
                end
                if strcmp(inputs.PresName,'psl')
                    t = double(ncread(tfile,inputs.TempAltName));
                    p = p_surf(p,t,ht); % Convert to surface pressure
                end
                VP = cat(3,VP,VapourPressure(SH,p));
            end
        end
    end
end


%% Load temperature file
disp('Loading temperature data...')
% Find temperature files:
froot = Tempdirin; % Take the file name...
files = dir([froot '*.nc']); % Then check if any files exist with this root

if ~isempty(files)
    for f = 1:length(files)
        file = [files(f).folder,'/',files(f).name];
        
        % Load temperature for the correct region and concatenate through time if necessary
        if f == 1
            T = ncread(file,inputs.TempName);
            dates = ncread(file,datename);
            
            % Some netCDFs have this saved in different orientation (e.g.
            % bias corrected data vs UKCP18 raw). Figure out which way it
            % is oriented to concatenate appropriately:
            s2 = size(dates);
            if s2(1) > s2(2)
                datedim = 1;
            else
                datedim = 2;
            end
            times = ncread(file,timename);
            x = ncread(file,xname);
            y = ncread(file,yname);
        else
            T = cat(3,T,ncread(file,inputs.TempName));
            dates = cat(datedim,dates,ncread(file,datename));
            times = cat(1,times,ncread(file,timename));
        end
    end
end

if datedim == 1
    dates = dates';
end

dates2 = dates';
% Correct the date stamp
y1 = str2double(string(dates2(:,1:4)));
m1 = str2double(string(dates2(:,5:6)));
d1 = str2double(string(dates2(:,7:8)));
ts1 = datetime(y1,m1,d1);
ts2 = datetime(1970,01,01);
times2 = hours(ts1 - ts2);
times = times2;


%% Calculate heat stress metric
if strcmp(inputs.Metric,'sWBGT')
    data = SWBGTVP(T,VP);
%     units = '°C';
    Variable = 'sWBGT';
    long_name = ['Daily ',char(inputs.MaxMeanMin),' simplified Wet Bulb Globe Temperature'];
    description = ['Daily ',char(inputs.MaxMeanMin),' simplified Wet Bulb Globe Temperature'];
%     label_units = '°C';
    plot_label = 'simplified WBGT';
elseif strcmp(inputs.Metric,'Humidex')
    data = HumidexVP(T,VP);
%     units = '°C';
    Variable = 'Humidex';
    long_name = ['Daily ',char(inputs.MaxMeanMin),' Humidex'];
    description = ['Daily ',char(inputs.MaxMeanMin),' Humidex'];
%     label_units = '°C';
    plot_label = 'Humidex';
elseif strcmp(inputs.Metric,'AppTemp')
    data = AppTempVP(T,VP);
%     units = '°C';
    Variable = 'AppTemp';
    long_name = ['Daily ',char(inputs.MaxMeanMin),' Apparent Temperature'];
    description = ['Daily ',char(inputs.MaxMeanMin),' Apparent Temperature'];
%     label_units = '°C';
    plot_label = 'Apparent Temperature';
elseif strcmp(inputs.Metric,'THI')
    data = TempHumidityIndexVP(T,VP);
%     units = '°C';
    Variable = 'THI';
    long_name = ['Daily ',char(inputs.MaxMeanMin),' Temperature Humidity Index'];
    description = ['Daily ',char(inputs.MaxMeanMin),' Temperature Humidity Index'];
%     label_units = '°C';
    plot_label = 'Temperature Humidity Index';
end    


%% Save output
% Create output directory/filename
fname_long = strcat(outdir,'/',inputs.ExptName,'_',Variable,inputs.MaxMeanMin,'_',(dates(1:8,1)'),'-',(dates(1:8,end)'),'.nc')
fname = strcat(inputs.ExptName,'_',Variable,inputs.MaxMeanMin,'_',(dates(1:8,1)'),'-',(dates(1:8,end)'),'.nc');

% Create netCDF and derived variable
nccreate(fname_long,Variable,'Dimensions',{'projection_x_coordinate',length(x),'projection_y_coordinate',length(y),'time',length(data(1,1,:))},'Datatype','double','Format','netcdf4_classic','DeflateLevel',2)
ncwrite(fname_long,Variable,data);
ncwriteatt(fname_long,Variable,'standard_name',Variable);
ncwriteatt(fname_long,Variable,'long_name',long_name);
% ncwriteatt(fname_long,Variable,'units',units);
ncwriteatt(fname_long,Variable,'description',description);
% ncwriteatt(fname_long,Variable,'label_units',label_units);
ncwriteatt(fname_long,Variable,'plot_label',plot_label);
ncwriteatt(fname_long,Variable,'coordinates','ensemble_member_id latitude longitude month_number year yyyymmdd');
ncwriteatt(fname_long,Variable,'missing_value',-9999);

% Add time and date data
% Some attributes are easier to read from template than to define
% manually as they change between simulations
% units = ncreadatt(template,'time','units');
% cal = ncreadatt(template,'time','calendar');

nccreate(fname_long,'time','Dimensions',{'time',length(data(1,1,:))},'Datatype','single','Format','netcdf4_classic','DeflateLevel',2)
ncwrite(fname_long,'time',times);
ncwriteatt(fname_long,'time','standard_name','time');
ncwriteatt(fname_long,'time','axis','T');

nccreate(fname_long,'yyyymmdd','Dimensions',{'time',length(data(1,1,:)),'string64',64},'Datatype','char')
ncwrite(fname_long,'yyyymmdd',dates');
ncwriteatt(fname_long,'yyyymmdd','long_name','yyyymmdd');
ncwriteatt(fname_long,'yyyymmdd','units','1');

% Add lat and long data
nccreate(fname_long,'projection_x_coordinate','Dimensions',{'projection_x_coordinate',length(x)},'Datatype','single','Format','netcdf4_classic','DeflateLevel',2)
ncwrite(fname_long,'projection_x_coordinate',x);
ncwriteatt(fname_long,'projection_x_coordinate','axis','X');

nccreate(fname_long,'projection_y_coordinate','Dimensions',{'projection_y_coordinate',length(y)},'Datatype','single','Format','netcdf4_classic','DeflateLevel',2)
ncwrite(fname_long,'projection_y_coordinate',y);
ncwriteatt(fname_long,'projection_y_coordinate','axis','Y');

% Write some general attributes
ncwriteatt(fname_long,'/','collection','HEAT-stress derived heat stress metric')
ncwriteatt(fname_long,'/','creation_date',datestr(now))
%     ncwriteatt(fname_long,'/','domain',fname(11:12))
ncwriteatt(fname_long,'/','title','HEAT-stress output')
ncwriteatt(fname_long,'/','version','HEAT-stress v1.0')


% Add meta data if same format as UKCP18 data
if inputs.UKCP18 == 1
    ncwriteatt(fname_long,Variable,'grid_mapping','transverse_mercator');
    
    ncwriteatt(fname_long,'projection_x_coordinate','standard_name','easting');
    ncwriteatt(fname_long,'projection_x_coordinate','long_name','easting');
    ncwriteatt(fname_long,'projection_x_coordinate','units','m');
    
    ncwriteatt(fname_long,'projection_y_coordinate','standard_name','northing');
    ncwriteatt(fname_long,'projection_y_coordinate','long_name','northing');
    ncwriteatt(fname_long,'projection_y_coordinate','units','m');
    
    ncwriteatt(fname_long,'time','units','hours since 1970-01-01 00:00:00');
%     ncwriteatt(fname_long,'time','calendar','365_day');
end

% To do: add option for ERA5?

disp(['Saving of ',char(fname),' complete'])
disp('-----')


%% Finish up
disp(' ')
disp(['HEAT-stress run "',char(inputs.ExptName),'" complete',])
endt = now;
fprintf('Total time taken to run: %s\n', datestr(endt-startt,'HH:MM:SS'))
disp('-----')


