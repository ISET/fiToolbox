close all;
clear variables;
clc;

dataset = 'McNamara-Boswell';
height = 4;
width = 6;
flQe = 0.1;
nFluorophores = 1;
fName = fullfile(fiToolboxRootPath,'data','simulations',sprintf('%s_%ix%ix%i_qe_%.2f.mat',dataset,height,width,nFluorophores,flQe));
load(fName);

deltaL = wave(2) - wave(1);
nWaves = length(wave);

alpha = 0.01;
beta = 0.01;
eta = 0.01;

nNoiseLevels = 20;
nInstances = 10;
noiseLevels = logspace(-4,2,nNoiseLevels);



% Create basis function sets
nReflBasis = 5;
nExBasis = 12;
nEmBasis = 12;

[reflBasis, reflScore] = createBasisSet('reflectance','wave',wave','n',nReflBasis);
[exBasis, exScore] = createBasisSet('excitation','wave',wave','n',nExBasis);
[emBasis, emScore] = createBasisSet('emission','wave',wave','n',nEmBasis);


% Load the light spectra (in photons)
fName = fullfile(fiToolboxRootPath,'camera','illuminants');
illuminant = ieReadSpectra(fName,wave);
illuminant = Energy2Quanta(wave,illuminant);
nChannels = size(illuminant,2);

% Load camera spectral properties
fName = fullfile(fiToolboxRootPath,'camera','filters');
filters = ieReadSpectra(fName,wave);

fName = fullfile(fiToolboxRootPath,'camera','qe');
qe = ieReadSpectra(fName,wave);

camera = diag(qe)*filters;
nFilters = size(camera,2);
   

nSamples = size(measVals,3);

reflEst = cell(nNoiseLevels,nInstances);
dMatEst = cell(nNoiseLevels,nInstances);
reflValsEst = cell(nNoiseLevels,nInstances);
flValsEst = cell(nNoiseLevels,nInstances);
measValsNoise = cell(nNoiseLevels,nInstances);

SNR = cell(nNoiseLevels,1);

try
    matlabpool open local
catch
end

 parfor nl=1:nNoiseLevels
    
    SNR{nl} = measVals./noiseLevels(nl);
    
    for i=1:nInstances
        
        measValsNoise{nl,i} = max(measVals + randn(size(measVals))*noiseLevels(nl),0);
        
        localCameraGain = repmat(cameraGain,[1 1 nSamples]);
        localCameraOffset = repmat(cameraOffset,[1 1 nSamples]);
        
        nF = max(max(measValsNoise{nl,i},[],1),[],2);
        localCameraGain = localCameraGain./repmat(nF,[nFilters nChannels 1]);
        measValsNoise{nl,i} = measValsNoise{nl,i}./repmat(nF,[nFilters nChannels 1]);
        
        [ reflEst{nl,i}, ~, ~, ~, ~, ~, dMatEst{nl,i}, reflValsEst{nl,i}, flValsEst{nl,i}, hist  ] = ...
            fiRecReflAndMultiFl( measValsNoise{nl,i}, camera, illuminant, localCameraGain*deltaL,...
            localCameraOffset, reflBasis, emBasis, exBasis, alpha, beta, beta, eta, 'maxIter',250);
        
    end
    
 end
 
 
try 
    matlabpool close
catch
end

 
 
 %% Average SNR across the patches for a given condition
SNRdB = zeros(nNoiseLevels,1);
for n=1:nNoiseLevels
    
    tmp = SNR{n};
    tmp = 10*log10(tmp);
    
    SNRdB(n) = mean(tmp(:));
end




%% Pixel error

pixelErr = zeros(nSamples,nNoiseLevels,nInstances);
for n=1:nNoiseLevels
    for i=1:nInstances
        est = reflValsEst{n,i} + flValsEst{n,i};
        for s=1:nSamples
            pixelErr(s,n,i) = fiComputeError(reshape(est(:,:,s),nFilters*nChannels,1),reshape(measValsNoise{n,i}(:,:,s),nFilters*nChannels,1),'absolute');
        end
    end
end

avgPixelErr = mean(pixelErr,3);
avgPixelErr = mean(avgPixelErr,1);

stdPixelErr = std(pixelErr,[],3);
stdPixelErr = mean(stdPixelErr,1)/sqrt(nInstances);

%% Reflectance error

reflErr = zeros(nSamples,nNoiseLevels,nInstances);
for n=1:nNoiseLevels
    for i=1:nInstances
        est = reflEst{n,i};
        for s=1:nSamples
            reflErr(s,n,i) = fiComputeError(est(:,s),reflRef(:,s),'absolute');
        end
    end
end

avgReflErr = mean(reflErr,3);
avgReflErr = mean(avgReflErr,1);

stdReflErr = std(reflErr,[],3);
stdReflErr = mean(stdReflErr,1)/sqrt(nInstances);

%% Donaldson matrix error

dMatErr = zeros(nSamples,nNoiseLevels,nInstances);
for n=1:nNoiseLevels
    for i=1:nInstances
        est = dMatEst{n,i};
        for s=1:nSamples
            dMatErr(s,n,i) = fiComputeError(est(s),dMatRef(s),'normalized');
        end
    end
end

avgDMatErr = nanmean(dMatErr,3);
avgDMatErr = nanmean(avgDMatErr,1);

stdDMatErr = nanstd(dMatErr,[],3);
stdDMatErr = nanmean(stdDMatErr,1)/sqrt(nInstances);
 

fName = fullfile(fiToolboxRootPath,'results','evaluation',sprintf('%s_simSNR_multiFl.mat',dataset));
save(fName,'SNRdB','avgPixelErr','stdPixelErr','avgDMatErr','stdDMatErr',...
           'avgReflErr','stdReflErr','alpha','beta','eta',...
           'nNoiseLevels','nInstances','noiseLevels','nSamples','nFilters','nChannels');




