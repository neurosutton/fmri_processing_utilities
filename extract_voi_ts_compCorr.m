function [pca_regressors] = extract_voi_ts_compCorr(fmri_files,roi_files)

% Extract physiologic regressors for fMRI analysis. Currently, the script
% is set to run white matter and csf eroded masks, but the input should be
% modified to allow for flexible regressor naming.
%
% Summer 2019
% Brianne Sutton, PhD

if isempty(which('pca'))
    print('Stats folder was not on path. May have issues that require restoring default path.');
    addpath(genpath('/usr/local/MATLAB/R2017a/toolbox/stats'));
end

fmri_files = char(fmri_files);

if ~exist ('roi_files','var')
    csf_file = fullfile(which('ecsf_45.nii'));
    wm_file  = fullfile(which('ewhite_45.nii'));
    roi_files = char(wm_file, csf_file);
elseif ~iscell(roi_files)
    display('Formatting array')
    [n_rows,~] = size(roi_files);
    rowDist = ones(n_rows,1);
    roi_files = char(mat2cell(roi_files,rowDist));
end
templates = 'yes';
[out_dir,~,~]=fileparts(fmri_files);
thresholds = [];
for t=1:size(roi_files,2)
    v=spm_vol(roi_files{t});
    img=spm_read_vols(v);
    new_thresh = .7*max(reshape(img,{},1));
    thresholds = [thresholds, new_thresh];
end
n_components=3;
force_coregister='Yes';
    
%%
%function [R_noise_rois, noise_rois, verbose] = tapas_physio_create_noise_rois_regressors(...
   % noise_rois, verbose)


% Compute physiological regressors by extracting principal components of
% the preprocessed fMRI time series from anatomically defined noise ROIS (e.g. CSF)
%
% [pca_regressors, verbose] = tapas_physio_create_noise_rois_regressors(...
%     noise_rois, verbose)
%
% NOTE: The mean of all time series in each ROI will also be added as a regressor
% automatically
%
% Approach similar to the one described as aCompCor:
% Behzadi, Y., Restom, K., Liau, J., Liu, T.T., 2007.
% A component based noise correction method (CompCor) for BOLD and
% perfusion based fMRI. NeuroImage 37, 90?101.
% doi:10.1016/j.neuroimage.2007.04.042
%
% IN
%   physio.model.noise_rois
% OUT
%
% EXAMPLE
%   tapas_physio_create_noise_rois_regressors
%
%   See also spm_ov_roi

% Author: Lars Kasper
% Created: 2015-07-22
% Copyright (C) 2015 TNU, Institute for Biomedical Engineering,
%                    University of Zurich and ETH Zurich.
%
% This file is part of the TAPAS PhysIO Toolbox, which is released under the terms of the GNU General Public
% License (GPL), version 3. You can redistribute it and/or modify it under the terms of the GPL
% (either version 3 or, at your option, any later version). For further details, see the file
% COPYING or <http://www.gnu.org/licenses/>.
%%

if isempty(fmri_files) || isempty(roi_files)
    pca_regressors = [];
    return
end

if ~iscell(fmri_files)
    fmri_files = cellstr(fmri_files);
end

if ~iscell(roi_files)
    roi_files = cellstr(roi_files);
end

nRois = numel(roi_files);

if numel(thresholds) == 1
    thresholds = repmat(thresholds, 1, nRois);
end

if numel(n_components) == 1
    n_components = repmat(n_components, 1, nRois);
end

Vimg = []; for iFile = 1:numel(fmri_files), Vimg = [Vimg; spm_vol(fmri_files{iFile})];end
Yimg = spm_read_vols(Vimg);

nVolumes = size(Yimg, 4);
Yimg = reshape(Yimg, [], nVolumes);

pca_regressors = [];
for r = 1:nRois
    
    nComponents =  n_components(r);
    threshold = thresholds(r);
    fileRoi = roi_files{r};
    
    Vroi = spm_vol(fileRoi);
    
   hasRoiDifferentGeometry = any(any(abs(Vroi.mat - Vimg(1).mat) > 1e-5)) | ...
       any(Vroi.dim-Vimg(1).dim(1:3));
  perform_coreg = strcmpi(force_coregister,'Yes') || isequal(force_coregister, 1);
    
    %Force coregistration ?
   if ~perform_coreg && hasRoiDifferentGeometry % still check the geometry !! very important !!
       perform_coreg = true;
       warning(sprintf('fMRI volume and noise ROI have different orientation : \n %s \n %s \n', Vimg(1).fname, Vroi.fname)); %#ok<SPWRN>
   end
    
    if perform_coreg
        
        % estimate & reslice to same geometry
        matlabbatch{1}.spm.spatial.coreg.estwrite.ref = { sprintf('%s,1',fmri_files{1}) }; % select the first volume
        matlabbatch{1}.spm.spatial.coreg.estwrite.source = roi_files(r);
        matlabbatch{1}.spm.spatial.coreg.estwrite.other = {''};
        matlabbatch{1}.spm.spatial.coreg.estwrite.eoptions.cost_fun = 'nmi';
        matlabbatch{1}.spm.spatial.coreg.estwrite.eoptions.sep = [4 2];
        matlabbatch{1}.spm.spatial.coreg.estwrite.eoptions.tol = [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001];
        matlabbatch{1}.spm.spatial.coreg.estwrite.eoptions.fwhm = [7 7];
        matlabbatch{1}.spm.spatial.coreg.estwrite.roptions.interp = 4;
        matlabbatch{1}.spm.spatial.coreg.estwrite.roptions.wrap = [0 0 0];
        matlabbatch{1}.spm.spatial.coreg.estwrite.roptions.mask = 0;
        matlabbatch{1}.spm.spatial.coreg.estwrite.roptions.prefix = 'r';
        
        spm_jobman('run', matlabbatch);
        
        % update header link to new reslice mask-file
        Vroi = spm_vol(spm_file(fileRoi, 'prefix', 'r'));
    end
    
    roi = spm_read_vols(Vroi); % 3D matrix of the ROI
    roi(roi <  threshold) = 0;
    roi(roi >= threshold) = 1;
     
    % Write the final noise ROIs in a volume, after relice, threshold and erosion
    [fpRoi,fnRoi] = fileparts(Vroi.fname);
    Vroi.fname = fullfile(fpRoi, sprintf('noiseROI_%s.nii', fnRoi));
    spm_write_vol(Vroi,roi);
%     
%     % Overlay the final noise ROI (code from spm_orthviews:add_c_image)
%     if verbose.level >= 2
%         spm_check_registration( roi_files{:} );
%         spm_orthviews('addcolouredimage',r,Vroi.fname ,[1 0 0]);
%         hlabel = sprintf('%s (%s)',Vroi.fname ,'Red');
%         c_handle    = findobj(findobj(st.vols{r}.ax{1}.cm,'label','Overlay'),'Label','Remove coloured blobs');
%         ch_c_handle = get(c_handle,'Children');
%         set(c_handle,'Visible','on');
%         uimenu(ch_c_handle(2),'Label',hlabel,'ForegroundColor',[1 0 0],...
%             'Callback','c = get(gcbo,''UserData'');spm_orthviews(''context_menu'',''remove_c_blobs'',2,c);');
%         spm_orthviews('redraw')
%     end
%     
    Yroi = Yimg(roi(:)==1, :); % Time series of the fMRI volume in the noise ROIs
    
    %% mean and linear trend removal according to CompCor pub
    % design matrix
    X = ones(nVolumes,1);
    X(:,2) = 1:nVolumes;
    % fit 1st order polynomial to time series data in each voxel
    for n_roi_voxel = 1:size(Yroi,1)
        % extract data
        raw_Y = Yroi(n_roi_voxel,:)';
        % estimate betas
        beta = X\raw_Y;
        % fitted data
        fit_Y = X*beta;
        % detrend data
        detrend_Y = raw_Y - fit_Y;
        
        % overwrite Yroi
        Yroi(n_roi_voxel,:) = detrend_Y;
    end
    
    %%
    
    
    % COEFF = [nVolumes, nPCs]  principal components (PCs) ordered by variance
    %                           explained
    % SCORE = [nVoxel, nPCs]    loads of each component in each voxel, i.e.
    %                           specific contribution of each component in
    %                           a voxel's variance
    % LATENT = [nPCs, 1]        eigenvalues of data covariance matrix,
    %                           stating how much variance was explained by
    %                           each PC overall
    % TSQUARED = [nVoxels,1]    Hotelling's T-Squared test whether PC
    %                           explained significant variance in a voxel
    % EXPLAINED = [nPCs, 1]     relative amount of variance explained (in
    %                           percent) by each component
    % MU = [1, nVolumes]        mean of all time series
    [COEFF, SCORE, LATENT, TSQUARED, EXPLAINED, MU] = pca(Yroi);
    
    % components defined via threshold of variance explained
    if nComponents < 1
        nComponents = find(cumsum(EXPLAINED)/100 > nComponents, 1, 'first');
    end
    
    % save to return
    noise_rois.n_components(r) = nComponents + 1; % + 1 for mean
    
    % Take mean and some components into noise regressor
    R = MU';
    R = [R, COEFF(:,1:nComponents)];
    
    nRegressors = size(R,2);
    
    % z-transform
    stringLegend = cell(nRegressors,1);
    for c = 1:nRegressors
        R(:,c) = (R(:,c) - mean(R(:,c)))/std(R(:,c));
        
        if c > 1
            stringLegend{c} = ...
                sprintf('Principal component %d (%7.4f %% variance explained)', ...
                c-1, EXPLAINED(c-1));
        else
            stringLegend{c} = 'Mean time series of all voxels';
        end
    end
    
    % write away extracted PC-loads & roi of extraction
    [fpRoi,fnRoi] = fileparts(Vroi(1).fname);
    fpFmri = fileparts(Vimg(1).fname);
    for c = 1:nComponents
        Vpc = Vroi;
        Vpc.fname = fullfile(fpFmri, sprintf('pc%02d_scores_%s.nii',c, fnRoi));
        % saved as float, since was masked before
        Vpc.dt = [spm_type('float32') 1];
        pcScores = zeros(Vpc.dim);
        pcScores(roi(:)==1) = SCORE(:, c);
        spm_write_vol(Vpc, pcScores);
    end
    pca_regressors= [pca_regressors, R];
end

