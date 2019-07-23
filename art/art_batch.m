function art_batch(spmfiles)
% ART_BATCH
% batch processing of multiple subjects from SPM.mat files (one per subject)
%
% art_batch; prompts the user to select a list of SPM.mat files (one per
% subject) and runs ART using the default options on all of the subjects
% data.
% 
% art_batch(spm_files) 
% uses the SPM.mat files listed in the spm_files cell array
%
% see code for additional options
%

%%%%%%%%%%%% ART PARAMETERS (edit to desired values) %%%%%%%%%%%%
global_mean=1;                % global mean type (1: Standard 2: User-defined Mask)
motion_file_type=0;           % motion file type (0: SPM .txt file 1: FSL .par file 2:Siemens .txt file)
global_threshold=9.0;         % threshold for outlier detection based on global signal
motion_threshold=1.0;         % threshold for outlier detection based on motion estimates
use_diff_motion=1;            % 1: uses scan-to-scan motion to determine outliers; 0: uses absolute motion
use_diff_global=1;            % 1: uses scan-to-scan global signal change to determine outliers; 0: uses absolute global signal values
use_norms=1;                  % 1: uses composite motion measure (largest voxel movement) to determine outliers; 0: uses raw motion measures (translation/rotation parameters) 
mask_file=[];                 % set to user-defined mask file(s) for global signal estimation (if global_mean is set to 2) 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
STEPS=[1,1];

if STEPS(1),
    if nargin>0,files=char(spmfiles);
    else files=spm_select(Inf,'SPM\.mat','Select SPM.mat files (one per subject)');end
    for n1=1:size(files,1),
        cfgfile=fullfile(pwd,['art_config',num2str(n1,'%03d'),'.cfg']);
        fid=fopen(cfgfile,'wt');
        %[filepath,filename,fileext]=fileparts(deblank(files(n1,:)));
        load(deblank(files(n1,:)),'SPM');
        
        fprintf(fid,'# Automatic script generated by %s\n',mfilename);
        fprintf(fid,'# Users can edit this file and use\n');
        fprintf(fid,'#   art(''sess_file'',''%s'');\n',cfgfile);
        fprintf(fid,'# to launch art using this configuration\n');
        
        fprintf(fid,'sessions: %d\n',length(SPM.Sess));
        fprintf(fid,'global_mean: %d\n',global_mean);
        fprintf(fid,'global_threshold: %f\n',global_threshold);
        fprintf(fid,'motion_threshold: %f\n',motion_threshold);
        fprintf(fid,'motion_file_type: %d\n',motion_file_type);
        fprintf(fid,'motion_fname_from_image_fname: 1\n');
        fprintf(fid,'use_diff_motion: %d\n',use_diff_motion);
        fprintf(fid,'use_diff_global: %d\n',use_diff_global);
        fprintf(fid,'use_norms: %d\n',use_norms);
        fprintf(fid,'spm_file: %s\n',deblank(files(n1,:)));
        fprintf(fid,'output_dir: %s\n',art_fileparts(files(n1,:)));
        [x y z subj_dir] =  art_fileparts(files(n1,:)); %Added by BMM 160321
        fprintf(fid,'subj_dir: %s\n',subj_dir); %Added by BMM 160321
        raw_dir = strcat(subj_dir,filesep,'raw'); %Added by BMM 160321
        fprintf(fid,'raw_dir: %s\n',raw_dir); %Added by BMM 160321
        if ~isempty(mask_file),fprintf(fid,'mask_file: %s\n',deblank(mask_file(n1,:)));end
        fprintf(fid,'end\n');
        

            
        for n2=1:length(SPM.Sess),
            temp=[SPM.xY.P(SPM.Sess(n2).row,:),repmat(' ',[length(SPM.Sess(n2).row),1])]';
            fprintf(fid,'session %d image %s\n',n2,temp(:)');
        end
        fprintf(fid,'end\n');
        fclose(fid);
    end
end


if STEPS(2),
    for n1=1:size(files,1),
        cfgfile=fullfile(pwd,['art_config',num2str(n1,'%03d'),'.cfg']);
        disp(['running subject ',num2str(n1),' using config file ',cfgfile]);
        art('sess_file',cfgfile); %Changed from 'art' to 'art' eliminate 7th column 160324 BMM
        set(gcf,'name',['art_batch: art subject #',num2str(n1)]);

    end
end

end

% -----------------------------------------------------------------------
% ART_FILEPARTS
% Filename parts
% -----------------------------------------------------------------------
function [filename_path,filename_name,filename_ext,subj_dir]=art_fileparts(varargin)

filename_name=''; filename_ext='';
if ~nargin, filename_path=pwd; return; 
elseif nargin==1, filename=varargin{1}; 
else filename=fullfile(varargin{:});
end
if isempty(filename), filename_path=pwd; return; end
[filename_path,filename_name,filename_ext]=fileparts(filename);
[subj_dir] = fileparts(filename_path); %Added BMM 160321

if isempty(filename_path),
    filename_path=pwd;
else
    cwd=pwd;
    cd(filename_path);
    filename_path=pwd;
    cd(cwd);
end
end
