% Evaluate the multi fluorophore algorithm using simulated data captured
% with systems containing different numbers of illuminants and spectral
% channels.
%
% This script is computationally intense and may take a long time to run.
%
% Copyright, Henryk Blasinski 2016

close all;
clear all;
clc;

% Save results to file if saveFName ~= []
% saveFName = fullfile(fiToolboxRootPath,'results','evaluation',sprintf('%s_simNBands_multiFl.mat',dataset));
saveFName = [];

wave = 380:4:1000;
spSize = wave(end) - wave(1);
nWaves = length(wave);
deltaL = wave(2) - wave(1);

% Tuning parameters
alpha = 0.001;
beta = 0.001;
eta = 0.001;

% Number of filters and channels to evaluate
maxChannels = 30;
maxFilters = 30;

% Scene properties
flQe = 0.5;
nFluorophores = 1;
dataset = 'McNamara-Boswell';
height = 4;
width = 6;
nSamples = height*width;

% Reflectance basis
nReflBasis = 5;
nEmBasis = 12;
nExBasis = 12;
reflBasis = fiCreateBasisSet('reflectance','wave',wave','n',nReflBasis);
exBasis = fiCreateBasisSet('excitation','wave',wave','n',nExBasis);
emBasis = fiCreateBasisSet('emission','wave',wave','n',nEmBasis);


% Create reflective scene
scene = sceneCreate('macbethEE_IR','',wave);
scene = sceneSet(scene,'fov',5);
scene = sceneSet(scene,'distance',1);

fName = fullfile(isetRootPath,'data','surfaces','macbethChart');
reflRef = ieReadSpectra(fName,wave);

% Create fluorescent scene
flScene = fluorescentSceneCreate('height',height,'width',width,'wave',wave,'qe',flQe,'nFluorophores',nFluorophores,...
                                 'peakEmRange',[wave(5) wave(end-5)],...
                                 'peakExRange',[wave(5) wave(end-5)],...
                                 'dataSet',dataset);
         
dMatRef = fluorescentSceneGet(flScene,'Donaldson reference');        

[channelGrid, filterGrid] = meshgrid(1:maxChannels,1:maxFilters);

% Error placeholder variables
reflErr = zeros(maxChannels,maxFilters);
reflStd = zeros(maxChannels,maxFilters);

dMatErr = zeros(maxChannels,maxFilters);
dMatStd = zeros(maxChannels,maxFilters);

pixelErr = zeros(maxChannels,maxFilters);
pixelStd = zeros(maxChannels,maxFilters);


try
    cluster = parcluster('local');
    cluster.NumWorkers = min(numel(channelGrid),35);
    pool = parpool(cluster,cluster.NumWorkers);
catch
end

parfor i=1:numel(channelGrid);

    nFilters = filterGrid(i);
    nChannels = channelGrid(i);
    
    cameraGain = ones(nFilters,nChannels);
    cameraOffset = zeros(nFilters,nChannels);
    
    % Define a camera
    filterWidth = ceil(spSize/nFilters/deltaL);
    camera = zeros(nWaves,nFilters);
    for c=1:nFilters
        camera(min((c-1)*filterWidth+1:c*filterWidth,nWaves),c) = 1;
    end
    
    % Define illuminant
    illuminantWidth = ceil(spSize/nChannels/deltaL);
    illuminant = zeros(nWaves,nChannels);
    for c=1:nChannels
        illuminant(min((c-1)*illuminantWidth+1:c*illuminantWidth,nWaves),c) = 1;
    end
    

    [reflValsRef, flValsRef] = fiComputeReflFlContrib(camera,illuminant,cameraGain*deltaL,reflRef,dMatRef);
    measVals = reflValsRef + flValsRef;
    
    cameraGain = repmat(cameraGain,[1 1 nSamples]);
    cameraOffset = repmat(cameraOffset,[1 1 nSamples]);
    
    nF = max(max(measVals,[],1),[],2);
    nF = repmat(nF,[nFilters,nChannels,1]);
    measVals = measVals./nF;
    cameraGain = cameraGain./nF;
    
    
   
    
    [ reflEst, ~, emEst, ~, exEst, ~, dMatEst, reflValsEst, flValsEst, hist  ] = ...
    fiRecReflAndMultiFl( measVals, camera, illuminant, cameraGain*deltaL,...
                         cameraOffset, reflBasis, emBasis, exBasis, alpha, beta, beta, eta, 'maxIter',250,'rescaleRho',false);


    measValsEst = reflValsEst + flValsEst + cameraOffset;

    [pixelErr(i), pixelStd(i)] = fiComputeError(reshape(measValsEst,[nChannels*nFilters,nSamples]), reshape(measVals,[nChannels*nFilters,nSamples]), 'absolute');

    [reflErr(i), reflStd(i)] = fiComputeError(reflEst, reflRef, 'absolute');

    [dMatErr(i), dMatStd(i)] = fiComputeError(dMatEst, dMatRef, 'normalized');
                  

end

try
    delete(pool);
catch
end

if ~isempty(saveFName)
    save(saveFName,'pixelErr','pixelStd','dMatErr','dMatStd','reflErr','reflStd',...
        'filterGrid','channelGrid','alpha','beta','eta','dMatRef','reflRef',...
        'nReflBasis','nExBasis','nEmBasis');
end

