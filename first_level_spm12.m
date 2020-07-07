function first_level_spm12(subjs, taskArray)

% Purpose: Create first-level designs and contrasts for task-based fMRI
% Created: June 2017 by Brianne Sutton, PhD
% This function should handle single and multiple runs (with separate rp
% files)
% Required input: *design and constrast spreadsheets in the study folder*; smoothed and
% normalized EPIs
% NOTE: Not intended to run pre/post designs together. The script expects
% that the entered task folders are part of the same experiment.

extra_regs = 'no';  % For the delayed discounting, where reaction time is an extra covariate
taskPrefix = ''; %'ld_';
check_cons = 'no';
denoised = 0;
%special_task_name='primingfp' ; % Use if the contrasts or params
%spreadsheet has a different name than the general task (i.e., if you are
%mixing and matching tasks). Echo out, if not using.
%% Preliminary path and defaults
tool_dir = fileparts(fileparts(which('preproc_fmri')));
if isempty(which('file_selector'))
    addpath([tool_dir filesep 'general_utilities']);
end

[spm_home, template_home] = update_script_paths(tool_dir,'12');

hpf = 128; % High-pass filter value in Hz
tr = 2; % might be definable by spm_vol(image) > variable(a).private.timing.tspace, but I'm not sure

%% Set options
[special_templates runArt stc discard_dummies unwarp ignore_preproc dirName aCompCorr irepi] = preproc_fmri_firstLevel_inputVars_GUI; %allows for non-scripting users to alter the settings easily.
close(gcf);
if eq(unwarp,1)
    if eq(stc,1)
        % Unwarping is the only step that may have STC labels after it.
        % Thus, a specific order is needed here to locate the files.
        prefix = 'swau';
    else 
        prefix = 'swu'; % Can set the letters that are expected prior to standard naming scheme on the data (e.g., 'aruPerson1_task1_scanDate.nii')        
    end
    %regs = 'none';
elseif eq(irepi,1)
    prefix = 'sv';  % need to empty the variable option to make sure no blanks are propogated.
elseif eq(denoised,1)
    prefix = 'dsw';
else
    prefix = 'sw';
end

%% Get subject and study folder definitions
switch exist ('subjs')
    case 1
        [cwd,pth_subjdirs] = file_selector(subjs);
    otherwise
        [cwd,pth_subjdirs] = file_selector; %GUI to choose the main study directory
end

%% Note that task array order matters, if you have a pre/post design. Studies with "run1", "run2" will be automatically be ordered correctly. String-based descriptors will not have an inherent order.
switch exist ('taskArray')
    case 1
        [pth_taskdirs, taskArray] = file_selector_task(pth_subjdirs, taskArray);
    otherwise
        [pth_taskdirs, taskArray] = file_selector_task(pth_subjdirs);
end

taskCheck = split(taskArray,'_');
taskCheck = taskCheck(:,:,1); % Keep only the first split
taskNames = unique(taskCheck);

pth_subjdirs= pth_subjdirs(~cellfun('isempty', pth_subjdirs));
for l = 1:length(pth_taskdirs)
    pth_taskdirs(l).fileDirs = unique(pth_taskdirs(l).fileDirs);
    pth_taskdirs(l).fileDirs = pth_taskdirs(l).fileDirs(~cellfun('isempty', pth_taskdirs(l).fileDirs));
end

nRuns = length(taskNames);

if exist('special_task_name','var')
    % If mixing and matching tasks, then don't want to check for different
    % task prefixes.
    nTasks = 1; 
    sessrep = 'none';
else
    %runIx = strfind(taskArray,taskArray{1,1}(1:3));
    runIx = strfind(taskArray, taskNames{1,:}(1:2));
    runIx = ~cellfun('isempty',runIx);
    nRuns = max(find(runIx==1));   
    nTasks = max(find(runIx==0));
    if isempty (nTasks)
        nTasks = 1;
    end
    sessrep = 'repl';
end

projName = textscan(cwd,'%s','Delimiter','/');
projName = projName{1,1}{end};

%% Setup basics of the first-level
for iTask = 1:nTasks;
    task    = taskNames{iTask}; %stored from file_selector_task; code previously "pth_taskdirs(iTask).task"
    nFiles  = length(pth_taskdirs(iTask).fileDirs);
    for iSubj = 1:nFiles;
        subj_pth = char(pth_subjdirs{iSubj});
        [proj_dir subj unk] = fileparts(subj_pth(1,1:end-1)); %defines various pieces that are used to build paths and checks elsewhere.
        if ~ischar(unk) || isempty(unk)
            tmp = textscan(subj_pth,'%s','Delimiter','/');
            subj = tmp{1,1}{end};
            clear tmp
        end
        fprintf('\nWorking with subject %u of %u: %s\nTask:%s\n',iSubj,nFiles,subj,task);
 
        if length(subj) > 6
            subj_prefix = (subj(1:end-1)); %Also for multiple timepoints, where T1 is not collected at all timepoints
        else
            subj_prefix = subj;
        end
        
        ix = strfind(task,'_run'); %Specific to dir names with 'run' in them.
        if  exist('special_task_name' ,'var');
            taskName = special_task_name;
        elseif isempty(ix)
            taskName = task;
        else
            taskName = task(1:ix-1);
        end

        if eq(runArt,1) %from the checkbox setup
            results_dir = [subj_pth, filesep, taskName, '_resultsArt'];
        else
            results_dir = [subj_pth, filesep, taskName, '_results'];
        end

        if eq(unwarp,1)
            results_dir = [results_dir, '_unwarp'];
        end

        if eq(aCompCorr,1)
            results_dir = [results_dir, '_aCompCorr'];
        end
%results_dir = [subj_pth, filesep, 'Craving_Task'];
        if ~isempty (dirName) %capability to quickly run experiments on other processing options w/o overwriting the original results
            if ~contains(dirName,'Enter'); %'Enter special suffix here' doesn't need to be added... so skip changing the directory name, if the default was unchanged
                results_dir = [results_dir,'_',dirName];
            end
        end

        check = rdir(results_dir);
        if isempty(check);
            mkdir (results_dir);
        end

        check_spm = rdir ([results_dir, filesep, 'con_0001.nii']);
        spm_exists = (arrayfun(@(x) ~isempty(x.name),check_spm) == 1);
        if ~isempty(spm_exists) &&  eq(ignore_preproc,0)
            if strcmpi(check_cons, 'y')
                print_con_overview(results_dir, {1 2 3}, contrast_array);
            end
            for t = 1:size(taskArray,2)
                raw_dir= fullfile(subj_pth,taskArray{t})
                check_rp_plot(raw_dir);
            end
            disp('Continue with next participant');
            continue
        else
            if exist(strcat(results_dir, filesep, 'SPM.mat'),'file')
                delete (strcat(results_dir, filesep, 'SPM.mat')); %Or else GUI will pop up asking to overwrite. Supremely inconvenient for batching overnight
            end
            
            %% Check that all runs have been processed
            for r = 1: nRuns
                if strcmp(spm('ver'),'SPM8')
                   locateImg = glob([subj_pth,filesep,taskArray{r},filesep,[prefix,'*spm8.nii']]);
                else
                    locateImg = glob([subj_pth,filesep,taskArray{r},filesep,[prefix,'*.nii']]);
                    % Will probably need to be revisited to ensure the cell
                    % array is properly created in 133 to find minimum
                    % file name length.
                    if length(locateImg) > 1
                        val=cellfun(@(x) numel(x),locateImg); %compare the length of all the nii's
                        locateImg = locateImg{(val==min(val))}; % If there is an spm8 processed scan, it will be ignored.
                    elseif ~isempty(locateImg)
                        locateImg = locateImg{1};
                    end
                end
                
                if ~isempty(locateImg)
                    imgFiles = rdir(locateImg);
                else
                    imgFiles = '';
                end
            end

            if length(imgFiles) < 1
                fprintf('Please process first: %s\n',subj);
                %preproc_fmri(ver, templates, subjs, taskArray, stc)
                %preproc_fmri('12b','no', subj, taskName, 'no',0); % 0 for NO prefix
                continue
            else
                %% Continue with loading files for 2nd level
                sw_files = cell(length(taskArray),1); % just initializing cell array for the smoothed, normalized files; should be empty

                for t = 1: length(taskArray)
                    locateImg = [subj_pth,filesep,taskArray{t},'*',filesep,[prefix,'*.nii']];

                    imgFiles = rdir(locateImg);
                    findShort = cellfun(@(x) numel(x), {imgFiles.name}); % in case there are multiple processing pipelines completed on the same brain
                    imgNames = imgFiles(findShort == min(findShort));

                    if length(imgNames) > 1 %The ANALYZE and 3D NII condition
                        nVols = length(imgNames);
                        tmp_sw_files = cell(1,nVols);

                        for iOF = 1: nVols
                            tmp_sw_files{1,iOF} = imgNames(iOF).name;
                        end
                    elseif length(spm_vol(imgNames.name))>1 % The 4D NIFTI condition
                        nVols = spm_vol(imgNames.name);
                        nVols = length(nVols);
                        tmp_sw_files = cell(1,nVols);

                        for iOF = 1: nVols
                            tmp_sw_files{1,iOF} =char(strcat(imgNames.name,',', int2str(iOF)));
                        end
                    end
                    sw_files{t,1} = tmp_sw_files;
                end

                %% Best practice matlabbatch setup
                clear matlabbatch;
                disp('Initializing SPM batch variables');
                spm('defaults','FMRI');
                spm_jobman('initcfg');        

                %% Clean the file list
                for sw = 1: length(sw_files);
                    dropIx = []; %cleaning step
                    for w = 1:numel(sw_files{sw,1})
                        meanImg = [prefix,'mean'];
                        drop = strfind(sw_files{sw,1}(w),meanImg); % check each cell to see if it is a mean img
                        if ~isempty(drop{1,1})
                            dropIx = [dropIx w];
                        end
                    end
                    sw_files{sw,1}(dropIx) = []; %removes any entries fitting the exclusion criteria for that scan series
                end

                %% Defining the contrasts
                %contrast_design_file = rdir([proj_dir,filesep,'*', taskName,'*_contrasts*']);
                contrast_design_file = rdir([proj_dir,filesep, taskName,'*_contrasts*']);
                
                if length(contrast_design_file) == 0
                    fprintf('No contrasts defined for %s in %s\nPlease correct before continuing (Line 220)\n',taskName, proj_dir);
                    return
                end
                [~,~, raw] = xlsread(contrast_design_file.name); % Must contain the headers listed below, with data stacked vertically underneath.
                tIx = find(strcmp('title',raw(1,:))); %names for the top of the glass brains
                cIx = find(strcmp('matrix',raw(1,:))); %contrast vectors
                cIx_part2 = find(strcmp('matrix_2',raw(1,:))); % In the event you wish to model pre- and post- in the same first-level.
                kindIx = find(strcmp('con_type',raw(1,:))); % tcon or fcon (to increase flexibility
                sessRepIx = find(strcmp('sessRep',raw(1,:))); % Manual override for special designs (like pre/post), where you want to model timepoints separately.

                contrast_array = struct();
                contrast_array(1,1).title = raw(:,tIx);
                contrast_array(1,1).con = raw(:,cIx);
                contrast_array(1,1).con_part2 = raw(:, cIx_part2);
                contrast_array(1,1).kind = raw(:,kindIx);
                contrast_array(1,1).sessRep = raw(:,sessRepIx);

                nCons = length(contrast_array(1,1).con)-1;
                fprintf('Discovered %d contrasts to create\n',nCons);

                %% Entering the variables with some defaults.
                matlabbatch{1}.spm.stats.fmri_spec.dir = {results_dir};
                matlabbatch{1}.spm.stats.fmri_spec.timing.units = 'secs';
                matlabbatch{1}.spm.stats.fmri_spec.timing.RT = tr;
                matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t = 16;
                matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t0 = 8;
                matlabbatch{1}.spm.stats.fmri_spec.fact = struct('name', {}, 'levels', {});
                matlabbatch{1}.spm.stats.fmri_spec.bases.hrf.derivs = [0 0]; %Change here for different basis functions
                matlabbatch{1}.spm.stats.fmri_spec.volt = 1;
                matlabbatch{1}.spm.stats.fmri_spec.global = 'None';
                matlabbatch{1}.spm.stats.fmri_spec.mthresh = 0.2; %Lower this threshold from .8 for more inclusive analysis
                matlabbatch{1}.spm.stats.fmri_spec.mask = {''};
                matlabbatch{1}.spm.stats.fmri_spec.cvi = 'FAST'; %'AR(1)'
                matlabbatch{2}.spm.stats.fmri_est.spmmat(1) = cfg_dep('fMRI model specification: SPM.mat File', substruct('.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','spmmat'));
                matlabbatch{2}.spm.stats.fmri_est.write_residuals = 0;
                matlabbatch{2}.spm.stats.fmri_est.method.Classical = 1;

                %% Find smoothed files, condition regressors, and contrast files
                % Customized for number of runs

                parCheck = rdir([subj_pth,filesep, '*', taskName,'*_param*']) ;
                if ~isempty(parCheck)
                  % Case where ER-design with individual onset times.
                    study_design_file = rdir([subj_pth,filesep, taskPrefix,taskName,'*_param*']);
                else
                  % Case wher study-wide same design
                   study_design_file = rdir([proj_dir,filesep ,taskName,'*_param*']);
                end
                
                
                if isempty(study_design_file)
                    fprintf('Design parameters for %s in %s missing\nPlease correct before continuing\n',taskName, proj_dir);
                    continue
                end
                [~,~, raw] = xlsread(study_design_file.name); % Must contain the headers listed below, with data stacked vertically underneath.
                nIx = find(strcmp('names',raw(1,:)));
                onIx = find(strcmp('onsets',raw(1,:)));
                durIx = find(strcmp('durations',raw(1,:)));
                tIx = find(strcmp('task',raw(1,:)));
                if strcmpi('y', extra_regs)
                  rtIx = find(strcmp('rt',raw(1,:)));
                end
                for r = 1:nRuns
                    %% Set the parameters
                    % Originally problematic entry definitions for files with multiple runs
                    % (i.e. 4) when there are only 2 runs being compared.
                    % Rewritten below for greater flexibility
                    %nEntries = (length(raw(:,1))-1)/nRuns; %subtract one for header
                    %lastEntry  = int8(nEntries*r)+1;%plus one for header
                    %firstEntry = lastEntry-(nEntries-1);
                    
                    %% Use string comparisons to identify the correct lines from the table
                    current_task = taskArray{r};
                    taskEntries=find(strcmp(current_task,raw(:,tIx)));
                    lastEntry= taskEntries(end);
                    firstEntry = taskEntries(1);
                    
                    %% Grab the values associated with modeling the current task (i.e., the experimental condition names, onset values, and durations)
                    nVals = raw(firstEntry:lastEntry,nIx);
                    onVals = raw(firstEntry:lastEntry,onIx);
                    durVals = raw(firstEntry:lastEntry,durIx);
                    
                    if strcmpi('y', extra_regs)
                      rtVals = raw(firstEntry:lastEntry,rtIx);
                      % Hold this value for the rp file section below. That is where the regressors will go.
                    end

                    cndtn_array = struct();
                    cndtn_array(1,1).name = nVals;
                    cndtn_array(1,1).onset = onVals;
                    cndtn_array(1,1).dur = durVals;

                    %Obsolete code that is not super flexible for different numbers of collected volumes
                    %               nVols = numel(sw_files)/nRuns;
                    %               lastVol = nVols*r; %The number of scans that go with each run times the run number
                    %               firstVol = (nVols*(r-1))+1;
                    %               scan_files = cell(1,nVols);
                    %              for v = firstVol:lastVol
                    %                   tmp = v-firstVol+1;
                    %                  scan_files{tmp} = char(sw_files(v));
                    %               end
                    % Better solution (which required the sw_files to be defined with a cell):
                    scan_files = sw_files{r,1};

                    % Raw directory definition
                    raw_dir = fullfile(subj_pth, current_task); %removed filesep 02.2020

                    %% Define the nuisance regressors for the multiple regressors field in SPM
                    if eq(denoised,1)
                        disp('Working with denoised data');
                        rp_file.name = '';
                    else
                        if eq(runArt,1)
                            rp_file = rdir(strcat(raw_dir,filesep,'art_regression_outliers_and_movement*'));
                            if isempty(arrayfun(@(x) ~isempty(x),rp_file))
                                disp('Executing ART protocol');
                                art_mtncorr(subj, raw_dir);
                                rp_file = rdir(strcat(raw_dir,filesep,'art_regression_outliers_and_movement*'));
                            end

                            if exist('regs','var') %for unwarped analyses
                                rp_file = rdir(strcat(raw_dir,filesep,'art_regression_outliers_w*'));
                                if isempty(rp_file)
                                    rp_file = rdir(strcat(raw_dir,filesep,'art_regression_outliers_sw*'));
                                end
                            end

                            load(rp_file.name);
                            if exist('R','var')
                                % Tallies the frames identified for despiking
                                % so that we can insure all groups are equally
                                % estimated.
                                tps =size(R,2)-7;
                                art_report = strcat(proj_dir, filesep, 'art_frames_identified_', task, '.txt');
                                cmd = sprintf('echo %s %0d\t "Signal SD: 5.0; FD motion: 1.0" >> %s', subj, tps, art_report);
                                system(cmd);
                            end

                            nMtnRegs{r} = size(R,2); %R is the name of the matrix from the rp_file (runArt sets the name)

                        else
                            if ~exist('regs','var')
                                spm8rp_check = rdir(strcat(raw_dir,filesep,'rp*','spm8.txt'));
                                if ~isempty(spm8rp_check)
                                    delete(spm8rp_check.name); % rp's will be the same, so elminate extra copies of the text file
                                end
                                rp_file = rdir(strcat(raw_dir,filesep,'rp*','.txt'));
                                findShort = cellfun(@(x) numel(x), {rp_file.name});
                                rp_file = rp_file(findShort == min(findShort));
                                nMtnRegs{r} = 6; %standard motion regressors
                            else
                                rp_file = []; % for unwarping
                                rp_file.name = '';
                                nMtnRegs{r} = 0;
                            end
                        end

                        if ~exist(rp_file.name,'file')
                          plot_mtn_graphs_batch(rp_file.name);
                        end
                    
                        if strcmpi('y', extra_regs)
                          rpVals = load(rp_file.name);
                          rpVals = [rpVals.R, rtVals];
                          new_rp_file = [raw_dir,filesep,'tmp_mtnAndrt_regs.mat'];
                          save(new_rp_file,'rpVals');
                          rp_file = rdir(new_rp_file); % To load the rps with the newly added regressor automatically
                        end

                        if eq(aCompCorr,1)
                          rpVals = load(rp_file.name); % Loads a structure with "R" containing the regressors.
                          if isstruct(rpVals)
                              rpVals = rpVals.R;
                          end
                          try
                              physio = load(fullfile(raw_dir,'aCompCorr_regs.txt')); % Top three PC's and mean of WM and/or CSF 
                              R = [rpVals,physio]; %SPM expects the regressor to be called R
                              new_rp_file = fullfile(raw_dir,'mtnAndCompCorr.mat');
                              save(new_rp_file,'R');
                              rp_file = rdir(new_rp_file);
                              nMtnRegs{r} = size(R,2);
                          catch
                              fprintf('aCompCorr not completed\n');
                              break
                          end
                        end
                    end

                    %% Record the parameters in the batch
                    matlabbatch{1}.spm.stats.fmri_spec.sess(r).scans = scan_files';
                    for c = 1:(length(cndtn_array(1,1).name))
                        matlabbatch{1}.spm.stats.fmri_spec.sess(r).cond(c).name = (cndtn_array(1,1).name{c});
                        matlabbatch{1}.spm.stats.fmri_spec.sess(r).cond(c).onset = str2num(cndtn_array(1,1).onset{c});
                        matlabbatch{1}.spm.stats.fmri_spec.sess(r).cond(c).duration = str2num(cndtn_array(1,1).dur{c});
                    end
                    matlabbatch{1}.spm.stats.fmri_spec.sess(r).multi = {''};
                    matlabbatch{1}.spm.stats.fmri_spec.sess(r).regress = struct('name', {}, 'val', {});
                    matlabbatch{1}.spm.stats.fmri_spec.sess(r).multi_reg = {rp_file.name};
                    matlabbatch{1}.spm.stats.fmri_spec.sess(r).hpf = hpf;
                    matlabbatch{1}.spm.stats.fmri_spec.cvi = 'FAST'; % Better estimate than AR(1) is FAST
                    %matlabbatch{1}.spm.stats.fmri_spec.mask = {'/usr/local/MATLAB/tools/spm12/canonical/avg152T1_brain.nii,1'};

                    savefile = [subj_pth,filesep,'firstLevel_' taskPrefix taskName '_' subj '.mat'];
                    save(savefile, 'matlabbatch');
                end

                if nCons >1
                    matlabbatch{3}.spm.stats.con.spmmat(1) = cfg_dep('Model estimation: SPM.mat File', substruct('.','val', '{}',{2}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','spmmat'));
                    for j = 1:nCons
                        if strcmpi(contrast_array(1,1).kind{j+1},'tcon')
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.name = contrast_array(1,1).title{j+1};
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.weights = [str2num(contrast_array(1,1).con{j+1})]; %currently only accommodates 1 run...
                            if isempty(contrast_array(1,1).sessRep{j+1})|| sum(isnan(contrast_array(1,1).sessRep{j+1})) > 0
                                matlabbatch{3}.spm.stats.con.consess{j}.tcon.sessrep = sessrep;
                            else
                                matlabbatch{3}.spm.stats.con.consess{j}.tcon.sessrep = contrast_array(1,1).sessRep{j+1};
                            end
                        elseif strcmpi(contrast_array(1,1).kind{j+1},'tcon_post')
                            num_pre_conditions = length(str2num(contrast_array(1,1).con{j+1}));
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.name = contrast_array(1,1).title{j+1};
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.weights = [zeros(1,(num_pre_conditions+nMtnRegs{1})), str2num(contrast_array(1,1).con{j+1})]; %currently only accommodates 1 run...
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.sessrep = 'none';
                        elseif strcmpi(contrast_array(1,1).kind{j+1},'tcon_separated')
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.name = contrast_array(1,1).title{j+1};
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.weights = [str2num(contrast_array(1,1).con{j+1}), zeros(1,nMtnRegs{1}), str2num(contrast_array(1,1).con_part2{j+1})]; % con_part2 is the matrix_2 column
                            matlabbatch{3}.spm.stats.con.consess{j}.tcon.sessrep = 'none';                            
                        elseif strcmpi(contrast_array(1,1).kind{j+1},'fcon')
                            matlabbatch{3}.spm.stats.con.consess{j}.fcon.name = contrast_array(1,1).title{j+1};
                            matlabbatch{3}.spm.stats.con.consess{j}.fcon.weights = [str2num(contrast_array(1,1).con{j+1})];
                            % Only if you want to explicitly spell out the contrasts (not use the "repeat for each session" option) should you use this next line
                            %               matlabbatch{3}.spm.stats.con.consess{j}.fcon.weights = [str2num(contrast_array(1,1).con{j+1}), zeros(1,nMtnRegs),str2num(contrast_array(1,1).con{j+1})];
                            matlabbatch{3}.spm.stats.con.consess{j}.fcon.sessrep = sessrep;
                        else
                            fprintf('Missing contrast type (tcon or fcon) for %s\n', contrast_array(1,1).title{j+1});
                        end

                    end
                    matlabbatch{3}.spm.stats.con.delete = 0; %Add the SPM batch setup
                else
                    disp('Please run contrast manager and results report manually')
                end

                try
                    save(savefile, 'matlabbatch');
                    spm_jobman('run',matlabbatch);
                catch
                    sprintf('Had trouble with %s',subj)
                    continue
                end
                check_rp_plot(raw_dir);
                if strcmpi(check_cons, 'y')
                    print_con_overview(results_dir, {1 2 3}, contrast_array);
                end
            end
        end
    end
cd (proj_dir);
end

function check_rp_plot(raw_dir)
if contains(version, '2019b')
    rp_plot_name = glob(fullfile(raw_dir, strcat('plot_*.pdf')));
    if isempty(rp_plot_name)
        rp_file = rdir(strcat(raw_dir,filesep,'rp*','.txt'));
        findShort = cellfun(@(x) numel(x), {rp_file.name});
        rp_file = rp_file(findShort == min(findShort));
        plot_mtn_graphs_batch(rp_file.name)
    end
else
    sprintf('Will not be able to write rp plot, because %s is being used rather than R2019b or higher.\n',version)
end

function print_con_overview(results_dir, conditions, contrast_array)
[~,subj_name] = fileparts(fileparts(results_dir));
check_file = fullfile(results_dir, [subj_name '_spmResults.ps']);
if exist(strcat(results_dir, filesep, 'SPM.mat'),'file') && isempty(glob(check_file))
    spm('defaults','FMRI');
    matlabbatch{1}.spm.stats.results.spmmat(1) = cfg_dep('Contrast Manager: SPM.mat File', substruct('.','val', '{}',{3}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','spmmat'));
    k=1;
    spm_mat = {fullfile(results_dir, 'SPM.mat')};

    for k = 1:length(conditions)
        if exist('contrast_array','var')
            title = contrast_array(1,1).title{conditions{k}+1};
        else
            title = strcat("contrast ", int2str(conditions{k}));
        end   
        matlabbatch{1}.spm.stats.results.spmmat = spm_mat;
        matlabbatch{1}.spm.stats.results.conspec(k).titlestr = char(title);
        matlabbatch{1}.spm.stats.results.conspec(k).contrasts = conditions{k};
        matlabbatch{1}.spm.stats.results.conspec(k).threshdesc = 'none';
        matlabbatch{1}.spm.stats.results.conspec(k).thresh = 0.005;
        matlabbatch{1}.spm.stats.results.conspec(k).extent = 15;
        k=k+1;
    end

    k=k-1;
    matlabbatch{1}.spm.stats.results.conspec(k+1).titlestr = char(title);
    matlabbatch{1}.spm.stats.results.conspec(k+1).contrasts =  conditions{k};
    matlabbatch{1}.spm.stats.results.conspec(k+1).threshdesc = 'none';
    matlabbatch{1}.spm.stats.results.conspec(k+1).thresh = 0.99;
    matlabbatch{1}.spm.stats.results.conspec(k+1).extent = 0;

    matlabbatch{1}.spm.stats.results.units = 1;
    matlabbatch{1}.spm.stats.results.export{1}.ps = true;
    matlabbatch{1}.spm.stats.results.write.none = 1;
    savefile = [results_dir,filesep,'con_snapshot.mat'];
    save(savefile, 'matlabbatch');    
    spm_jobman('run',matlabbatch);
 
    %% Keep and rename the rp graphs
    mv_file = glob(fullfile(results_dir, 'spm*ps'));
    if ~isempty(mv_file) && ~isempty(check_file)    
        movefile(char(mv_file), char(check_file));
    else
        fprintf('%s\n%s',mv_file{:}, check_file)
    end

% 
%         spm_home = fileparts(which('spm'));
%         template = fullfile(spm_home,'canonical','avg152T1.nii');
%         con_img = fullfile(results_dir,['con_000' int2str(contrastOfInterest) '.nii']);
%         pic = plot_overlays(template, con_img);
%         savefig(pic, fullfile(results_dir,'check_coverage.fig'));
%         close(pic);
end



