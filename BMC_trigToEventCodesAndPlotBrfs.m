%BMC_trigToEventCodesAndPlotBrfs.m
%GOAL: load the previously filtered and saved brfs data, trigger, and plot
%
%   Version 1.1
%   Brock Carlson -- created 9/9/19
%   
%   Current plotting goal: plot brfs monocular fCSDs for each ori and eye
%   under scaled conditions to see if an effect exists.
%
%   DOES NOT TRIGGER TO PHOTO DIODE


clear

%% EDITABLE VARIABLES
filename = {'160102_E_brfs001'}';
% % % filename = {'160102_E_brfs001','160427_E_brfs001','160510_E_brfs001'}';
sinkAllocate = 'BMC_DfS';
pre = 50;
post = 1600;
TM = -pre:1:post;
nameSaveType = 'LFPandCSDof';


% Computer-specific editable variables 
if strcmp(getenv('USER'),'maierav')
    % @Alex -- fill in necessary information for your system here.
        % savefiledir = 'G:\LaCie\SfN 2019--figsAndMatVars\SfN 2019 figs\brfs conditions diagnostics';        
elseif strcmp(getenv('USERNAME'),'Brock Carlson')
    % variables for end of script
    savefiledir = 'G:\LaCie\SfN 2019--figsAndMatVars\SfN 2019 figs\Is there an effect in monocular CSD';
elseif ~ispc && strcmp(getenv('USERNAME'),'Brock')
    savefiledir = 'INSERT PATH HERE';
end



for a = 1:size(filename,1)
    clearvars -except a filename sinkAllocate pre post TM savefiledir nameSaveType
    
    disp(filename{a})
    

%% Computer-specific directories 
if strcmp(getenv('USER'),'maierav')
    % @Alex -- fill in necessary information for your system here.
        % %     addpath(genpath('/Users/alex 1/Desktop/LAB/Brock'));
        % %     drname        = {'/Users/alex 1/Desktop/LAB/Brock/Data'};
        % load session params
    %session params
    sessionParamDir = 'G:/LaCie';
elseif strcmp(getenv('USERNAME'),'Brock Carlson')
    addpath(genpath('G:\LaCie\all BRFS'));
    dataDirectory = strcat('G:\LaCie\all BRFS\',filename{a}(1:8));
    %session params
    sessionParamDir = 'G:/LaCie';

elseif ~ispc && strcmp(getenv('USERNAME'),'Brock')
    dataDirectory = strcat('/Volumes/Drobo/DATA/NEUROPHYS/carlsobm/',filename{a}(1:8));
    %session params
    sessionParamDir = '/Volumes/Drobo/DATA/NEUROPHYS/carlsobm/';
end




%% LOAD IN SESSION DATA
tic

cd(sessionParamDir)
load('SessionParams.mat')
    
switch sinkAllocate
    case 'BMC_DfS'
        SessionParams.EvalSink = SessionParams.BMC_DfS;
    case 'Old_DfS'
        SessionParams.EvalSink = SessionParams.Old_DfS;
end

% get info needed for day I'm analyzing
dayID = strfind(SessionParams.Date',str2double(filename{a}(1:6)));
PARAMS = SessionParams(dayID,:);

%Set Channel vector based on the number of electrode contacts
chans = 1:PARAMS.el;

%% LOAD PROCESSED DATA
cd(savefiledir)
loadname = strcat(nameSaveType,filename{a},'.mat');
load(loadname)



%% TRIGGER TO pEvC/pEvT at 1 kHz 
[grating,readGRATINGfile] = formatAndOpenGratingTxt(dataDirectory,filename{a});


%% DIG INTO PREALLOCATED VARIABLES

%% Load event event codes and times
readNEVfile = strcat(dataDirectory,filesep,filename{a},'.nev');
NEV = openNEV(readNEVfile,'noread','overwrite');
EventCodes      = NEV.Data.SerialDigitalIO.UnparsedData - 128;        % we don't know why we have to subtract 128 but we do
EventSamples    = NEV.Data.SerialDigitalIO.TimeStamp;                 % in samples 
EventTimes      = floor(NEV.Data.SerialDigitalIO.TimeStampSec.*1000); % convert to ms 
[pEvC, pEvT]    = parsEventCodesML(EventCodes,EventSamples);          % sorts codes, samps or times into trials
%% SORT pEvC/pEvT TO MATCH GRAITNG VARIABLE
% So far all of these data are from EVERY trial, including trials where
% animal breaks fixation. Lets get rid of those and make a new structure
% with the grating info and the stimulus onsets 

% Note, STIM.onsets, is now an index of the column position for the...
% stimulus onset in the 30kHz data. This is why, for using it with the ns2
% file, we need to downsample to STIM.onsetsdown.
STIM            = sortStimandTimeData(grating,pEvC,pEvT,'stim'); 
STIM.onsetsdown         = floor(STIM.onsets./30); % necessary even for ns2 file analysis and use of photo diode. pEvT is in 30kHz sampling time. 

STIM_BRFS = sortBrfsStimandTimeData(grating,pEvC,pEvT,PARAMS);


% get dimensions for preallocation
readNS2file = strcat(dataDirectory,filesep,filename{a},'.ns2');
NS2_Header      = openNSx(readNS2file,'noread');
contactLogical = strcmp({NS2_Header.ElectrodesInfo.ConnectorBank},PARAMS.V1bank{1,1}(2));
contactLabels = {NS2_Header.ElectrodesInfo(contactLogical).Label};
contactNum = size(contactLabels,2);
if contactNum ~= PARAMS.el
    error('Houston we have a problem') %I'm not totally sure this set-up will always work... BMC 8/26/19
end

%% TRIGGER SECTION
%%%
%%%
%%%
%% trig all onsets
numTriggers.STIM.onsetsdown = size(STIM.onsetsdown,1);

%preallocate
TRIG.ns2LFP         = NaN( contactNum,(post + pre + 1),numTriggers.STIM.onsetsdown); 
TRIG.ns2CSD         = NaN( contactNum,(post + pre + 1),numTriggers.STIM.onsetsdown);
    
%%% DATA MUST BE DOWNSAMPLED TO 1KH IN ORDER TO TRIGGER PROPERLY
for singleCh = 1:contactNum 
    for singleTrigger = 1:numTriggers.STIM.onsetsdown
        timeOfTrigger = STIM.onsetsdown(singleTrigger);
        windowOfTrigger = timeOfTrigger-pre:timeOfTrigger+post;
        % output is (Ch x time x triggerNumber)
        TRIG.ns2LFP(singleCh,:,singleTrigger)       = ns2LFP(singleCh,windowOfTrigger); 
        TRIG.ns2CSD(singleCh,:,singleTrigger)       = ns2CSD(singleCh,windowOfTrigger);

    end
end


%% trig brfs onsets

fields.STIM_BRFS = fieldnames(STIM_BRFS);
for ffstim=1:numel(fields.STIM_BRFS)

    if sum(strcmp(fieldnames(STIM_BRFS.(fields.STIM_BRFS{ffstim})),'start_noSoaDown')) == 1
        numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim}) = size(STIM_BRFS.(fields.STIM_BRFS{ffstim}).start_noSoaDown,1);
        %preallocate
        TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2LFP         = NaN( contactNum,(post + pre + 1),numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim})); 
        TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2CSD         = NaN( contactNum,(post + pre + 1),numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim}));
        %%% DATA MUST BE DOWNSAMPLED TO 1KH IN ORDER TO TRIGGER PROPERLY
        for singleCh = 1:contactNum 
            for singleTrigger = 1: numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim})
                timeOfTrigger = STIM_BRFS.(fields.STIM_BRFS{ffstim}).start_noSoaDown(singleTrigger);
                windowOfTrigger = timeOfTrigger-pre:timeOfTrigger+post;
                % output is (Ch x time x triggerNumber)
                TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2LFP(singleCh,:,singleTrigger)       = ns2LFP(singleCh,windowOfTrigger); 
                TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2CSD(singleCh,:,singleTrigger)       = ns2CSD(singleCh,windowOfTrigger);

            end
        end
        
    elseif sum(strcmp(fieldnames(STIM_BRFS.(fields.STIM_BRFS{ffstim})),'start1Down')) == 1
        numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim}) = size(STIM_BRFS.(fields.STIM_BRFS{ffstim}).start1Down,1);
        %preallocate
        TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2LFP         = NaN( contactNum,(post + pre + 1),numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim})); 
        TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2CSD         = NaN( contactNum,(post + pre + 1),numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim}));
        %%% DATA MUST BE DOWNSAMPLED TO 1KH IN ORDER TO TRIGGER PROPERLY
        for singleCh = 1:contactNum 
            for singleTrigger = 1: numTriggers.STIM_BRFS.(fields.STIM_BRFS{ffstim})
                timeOfTrigger = STIM_BRFS.(fields.STIM_BRFS{ffstim}).start1Down(singleTrigger);
                windowOfTrigger = timeOfTrigger-pre:timeOfTrigger+post;
                % output is (Ch x time x triggerNumber)
                TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2LFP(singleCh,:,singleTrigger)       = ns2LFP(singleCh,windowOfTrigger); 
                TRIG_BRFS.(fields.STIM_BRFS{ffstim}).ns2CSD(singleCh,:,singleTrigger)       = ns2CSD(singleCh,windowOfTrigger);

            end
        end

    else
        error('problem with triggering brfs')
    end       
end

    


%% AVERAGE AND BASELINE-CORRECT TRIGGERED DATA

%% Average
% Avgerage TRIG
fields.TRIG = fieldnames(TRIG);
for avtr=1:numel(fields.TRIG)
    AVG.(fields.TRIG{avtr})  = mean(TRIG.(fields.TRIG{avtr}),3);
end

firstfields.TRIG_BRFS = fieldnames(TRIG_BRFS);
for ffav = 1:numel(firstfields.TRIG_BRFS)
    subfields.TRIG_BRFS = fieldnames(TRIG_BRFS.(firstfields.TRIG_BRFS{ffav}));
    for avtr=1:numel(subfields.TRIG_BRFS)
        AVG_BRFS.(firstfields.TRIG_BRFS{ffav}).(subfields.TRIG_BRFS{avtr})  = mean(TRIG_BRFS.(firstfields.TRIG_BRFS{ffav}).(subfields.TRIG_BRFS{avtr}),3);
    end
end

%% Baseline corect
% bl AVG
fields.AVG = fieldnames(AVG);
for blavg=1:numel(fields.AVG)
    bl  = mean(AVG.(fields.AVG{blavg})(:,TM<0),2);
    BLavg.(fields.AVG{blavg})  = AVG.(fields.AVG{blavg}) - bl;
end

firstfields.AVG_BRFS = fieldnames(AVG_BRFS);
for ffbl = 1:numel(firstfields.AVG_BRFS)
    subfields.AVG_BRFS = fieldnames(AVG_BRFS.(firstfields.AVG_BRFS{ffbl}));
    for blavg=1:numel(subfields.AVG_BRFS)
        bl  = mean(AVG_BRFS.(firstfields.AVG_BRFS{ffbl}).(subfields.AVG_BRFS{blavg})(:,TM<0),2);
        BLavg_BRFS.(firstfields.AVG_BRFS{ffbl}).(subfields.AVG_BRFS{blavg})  = AVG_BRFS.(firstfields.AVG_BRFS{ffbl}).(subfields.AVG_BRFS{blavg}) - bl;
    end
end
%% Filter and interpolate CSD, ns2 and ns5
% AVG
AVG.ns2fCSD = filterCSD(AVG.ns2CSD);
AVG_BRFS.diop_simult_NPS.ns2fCSD = filterCSD(AVG_BRFS.diop_simult_NPS.ns2CSD);

% BLavg
BLavg.ns2fCSD       = filterCSD(BLavg.ns2CSD);
BLavg_BRFS.diop_simult_NPS.ns2fCSD = filterCSD(BLavg_BRFS.diop_simult_NPS.ns2CSD);

%% END OF UPDATE FROM 9/9/19
%%%%%
%%%%%
%%%%%
%%%%%%%%% EVERY TYPE OF BRFS CONDITION TRIGGERS PROPERLY!! NOW I JUST HAVE
%%%%%%%%% TO PLOT THE 4X4GRID. TOMORROW AM.

%% POSTPROCESS
% downsample and get PSD

%Downsample LFP so I can easily calculate the psd

%PSD

%% Align Across Days
    %
    % create alignment matrices if necessary at a later date
    %
    
%% PLOT 1,2,3,4,5
% LFP, CSDshadedLine, fCSD, aMUA, PSD
figure
%LFPline
subplot(1,3,1)
f_ShadedLinePlotbyDepth(BLavg_BRFS.diop_simult_NPS.ns2LFP,chans,TM,[],1)
plot([0 0], ylim,'k')
plot([800 800], ylim,'k')
title({'LFP',filename{a}}, 'Interpreter', 'none')
xlabel('time (ms)')
ylabel('Contacts indexed down from surface')

% CSD line
subplot(1,3,2)
f_ShadedLinePlotbyDepth(BLavg_BRFS.diop_simult_NPS.ns2CSD,chans,TM,[],1)
plot([0 0], ylim,'k')
plot([800 800], ylim,'k')
title({'CSD',filename{a}}, 'Interpreter', 'none')
xlabel('time (ms)')

% fCSD
subplot(1,3,3)
imagesc(TM,chans,BLavg_BRFS.diop_simult_NPS.ns2fCSD); 
colormap(flipud(jet));
climit = max(abs(get(gca,'CLim'))*.8);
set(gca,'CLim',[-climit climit],'Box','off','TickDir','out')
hold on;
plot([0 0], ylim,'k')
plot([800 800], ylim,'k')
clrbar = colorbar;
title({'interpolate CSD',filename{a}}, 'Interpreter', 'none')
xlabel('time (ms)')
clrbar.Label.String = 'nA/mm^3';

cd(savefiledir)

%% SAVE
% % % cd(savefiledir)
% % % saveas(gcf, filename{a}, 'fig')
% % % saveas(gcf, filename{a}, 'pdf')
% % % saveas(gcf, filename{a}, 'png')


end







