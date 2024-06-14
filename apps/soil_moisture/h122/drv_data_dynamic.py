"""
Class Features

Name:          drv_data_dynamic
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20230824'
Version:       '1.0.0'
"""

# -------------------------------------------------------------------------------------
# libraries
import logging
import os
import pandas as pd

from copy import deepcopy

from lib_info_args import logger_name
from lib_info_args import time_format_algorithm
from lib_info_args import (geo_dim_name_x, geo_dim_name_y, geo_coord_name_x, geo_coord_name_y,
                           geo_var_name_x, geo_var_name_y)

from lib_utils_time import set_time_file
from lib_utils_generic import make_folder, reset_folder
from lib_data_io_pickle import read_file_obj, write_file_obj
from lib_data_io_nc import read_file_nc, organize_file_nc, write_file_nc
from lib_data_io_tiff import organize_file_tiff, write_file_tiff
from lib_data_io_gzip import unzip_filename

from lib_utils_io import fill_string_with_time, search_file_with_asterisk
from lib_utils_zip import remove_zip_extension

from lib_fx_methods import organize_data, organize_time, organize_attrs, adapt_data, resample_data, mask_data

# set logger
alg_logger = logging.getLogger(logger_name)

# debug
import matplotlib.pylab as plt
# -------------------------------------------------------------------------------------


# -------------------------------------------------------------------------------------
# class driver data
class DrvData:

    # method to initialize class
    def __init__(self, alg_time_reference, alg_time_now, alg_time_datasets,
                 alg_static, alg_settings,
                 tag_section_flags='flags', tag_section_template='template',
                 tag_section_methods='methods', tag_section_datasets='datasets',
                 tag_section_log='log', tag_section_tmp='tmp'):

        self.alg_time_reference = alg_time_reference
        self.alg_time_now = alg_time_now
        self.alg_time_datasets = alg_time_datasets

        self.alg_static = alg_static

        self.alg_flags = alg_settings[tag_section_flags]
        self.alg_template = alg_settings[tag_section_template]
        self.alg_methods = alg_settings[tag_section_methods]

        self.alg_datasets_src = alg_settings[tag_section_datasets]['dynamic']['source']
        self.alg_datasets_anc_raw = alg_settings[tag_section_datasets]['dynamic']['ancillary']['raw']
        self.alg_datasets_anc_def = alg_settings[tag_section_datasets]['dynamic']['ancillary']['def']
        self.alg_datasets_dst = alg_settings[tag_section_datasets]['dynamic']['destination']

        self.alg_log = alg_settings[tag_section_log]
        self.alg_tmp = alg_settings[tag_section_tmp]

        self.tag_folder_name, self.tag_file_name = 'folder_name', 'file_name'
        self.tag_variables, self.tag_compression, self.tag_format = 'variables', 'compression', 'format'

        self.reset_datasets_anc_raw = self.alg_flags['reset_datasets_ancillary_raw']
        self.reset_datasets_anc_def = self.alg_flags['reset_datasets_ancillary_def']
        self.reset_datasets_dst = self.alg_flags['reset_datasets_destination']
        self.reset_logs = self.alg_flags['reset_logs']

        self.folder_name_src = self.alg_datasets_src[self.tag_folder_name]
        self.file_name_src = self.alg_datasets_src[self.tag_file_name]
        self.file_path_src = os.path.join(self.folder_name_src, self.file_name_src)
        self.format_src = self.alg_datasets_src[self.tag_format]
        self.compression_src = self.alg_datasets_src[self.tag_compression]
        self.variables_src = self.alg_datasets_src[self.tag_variables]

        self.folder_name_anc_raw = self.alg_datasets_anc_raw[self.tag_folder_name]
        self.file_name_anc_raw = self.alg_datasets_anc_raw[self.tag_file_name]
        self.file_path_anc_raw = os.path.join(self.folder_name_anc_raw, self.file_name_anc_raw)

        self.folder_name_anc_def = self.alg_datasets_anc_def[self.tag_folder_name]
        self.file_name_anc_def = self.alg_datasets_anc_def[self.tag_file_name]
        self.file_path_anc_def = os.path.join(self.folder_name_anc_def, self.file_name_anc_def)

        self.folder_name_dst = self.alg_datasets_dst[self.tag_folder_name]
        self.file_name_dst = self.alg_datasets_dst[self.tag_file_name]
        self.file_path_dst = os.path.join(self.folder_name_dst, self.file_name_dst)
        self.format_dst = self.alg_datasets_dst[self.tag_format]
        self.compression_dst = self.alg_datasets_dst[self.tag_compression]
        self.variables_dst = self.alg_datasets_dst[self.tag_variables]

        self.grid_geo_x_src, self.grid_geo_y_src = self.alg_static['grid_geo_x_src'], self.alg_static['grid_geo_y_src']
        self.transform_src, self.proj_src = self.alg_static['transform_src'], self.alg_static['proj_src']
        self.grid_geo_x_dst, self.grid_geo_y_dst = self.alg_static['grid_geo_x_dst'], self.alg_static['grid_geo_y_dst']
        self.transform_dst, self.proj_dst = self.alg_static['transform_dst'], self.alg_static['proj_dst']

        self.settings_organize_data = self.alg_methods['organize_data']
        self.settings_resample_data = self.alg_methods['resample_data']
        self.settings_mask_data = self.alg_methods['mask_data']

    # method to organize data
    def organize_data(self):

        # info start method
        alg_logger.info(' ---> Organize dynamic datasets ... ')

        # get time reference and time now
        alg_time_reference = self.alg_time_reference
        alg_time_now = self.alg_time_now

        # get file path
        file_path_src_tmpl = self.file_path_src
        file_path_anc_raw_tmpl, file_path_anc_def_tmpl = self.file_path_anc_raw, self.file_path_anc_def
        file_path_dst_tmpl = self.file_path_dst

        # method to fill the filename(s)
        file_path_anc_raw_step = fill_string_with_time(file_path_anc_raw_tmpl, alg_time_reference, self.alg_template)
        file_path_anc_def_step = fill_string_with_time(file_path_anc_def_tmpl, alg_time_reference, self.alg_template)
        file_path_dst_step = fill_string_with_time(file_path_dst_tmpl, alg_time_reference, self.alg_template)

        # clean ancillary datasets (if ancillary flag(s) is activated)
        if self.reset_datasets_anc_raw or self.reset_datasets_anc_def:
            if os.path.exists(file_path_anc_raw_step):
                os.remove(file_path_anc_raw_step)
            if os.path.exists(file_path_anc_def_step):
                os.remove(file_path_anc_def_step)
            if os.path.exists(file_path_dst_step):
                os.remove(file_path_dst_step)
        # clean destination datasets (if ancillary flag(s) is activated)
        if self.reset_datasets_dst:
            if os.path.exists(file_path_dst_step):
                os.remove(file_path_dst_step)
        # clean ancillary and destination datasets if are not available together
        if (not os.path.exists(file_path_anc_raw_step)) and (not os.path.exists(file_path_dst_step)):
            if os.path.exists(file_path_anc_raw_step):
                os.remove(file_path_anc_raw_step)
            if os.path.exists(file_path_anc_def_step):
                os.remove(file_path_anc_def_step)
            if os.path.exists(file_path_dst_step):
                os.remove(file_path_dst_step)

        # info start time reference
        alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) + '" ... ')

        # check file ancillary availability
        if not os.path.exists(file_path_anc_raw_step):

            # iterate over time file(s)
            vars_src_collection, time_src_collection, attrs_src_collection = None, None, None
            for alg_time_step in self.alg_time_datasets:

                # info start time step
                alg_logger.info(' -----> Time subset "' + alg_time_step.strftime(time_format_algorithm) + '" ... ')

                # method to fill the filename(s)
                file_path_src_generic = fill_string_with_time(file_path_src_tmpl, alg_time_step, self.alg_template)
                # method to search file with asterisk (list of files)
                file_path_src_list = search_file_with_asterisk(file_path_src_generic)

                # check file list availability
                if file_path_src_list:

                    # iterate over file list source
                    for file_path_src_step in file_path_src_list:

                        # info start file step
                        alg_logger.info(' ------> Read file "' + file_path_src_step + '" ... ')

                        # check file source availability
                        if os.path.exists(file_path_src_step):

                            # check compression mode
                            if self.compression_src:
                                file_path_tmp_step = remove_zip_extension(file_path_src_step)
                                unzip_filename(file_path_src_step, file_path_tmp_step)
                            else:
                                file_path_tmp_step = deepcopy(file_path_src_step)

                            # get dataset source
                            obj_data_src, obj_attrs_src, obj_geo_src, obj_time_src = read_file_nc(
                                file_path_tmp_step, file_time_reference=alg_time_now,
                                file_variables=self.variables_src)

                            # organize variable(s) source
                            vars_src_step = organize_data(obj_data_src, obj_geo_src, **self.settings_organize_data)
                            # organize time(s) source
                            time_src_step = organize_time(obj_time_src, time_index='time_creation')
                            # organize attr(s) source
                            attrs_src_step = organize_attrs(obj_attrs_src, attr_index='date_created_utc')

                            # check variable dataframe availability
                            if not vars_src_step.empty:
                                # store variable(s) source
                                if vars_src_collection is None:
                                    vars_src_collection = deepcopy(vars_src_step)
                                else:
                                    vars_src_collection = pd.concat([vars_src_collection, vars_src_step], axis=0)

                            # check time dataframe availability
                            if not time_src_step.empty:
                                # store time source
                                if time_src_collection is None:
                                    time_src_collection = deepcopy(time_src_step)
                                else:
                                    time_src_collection = pd.concat([time_src_collection, time_src_step], axis=0)

                            # check attrs dataframe availability
                            if not attrs_src_step.empty:
                                # store attrs source
                                if attrs_src_collection is None:
                                    attrs_src_collection = deepcopy(attrs_src_step)
                                else:
                                    attrs_src_collection = pd.concat([attrs_src_collection, attrs_src_step], axis=0)

                            # delete uncompressed file (if needed)
                            if self.compression_src:
                                if os.path.exists(file_path_tmp_step):
                                    os.remove(file_path_tmp_step)

                            # info start file step
                            alg_logger.info(' ------> Read file "' + file_path_src_step + '" ... DONE ')

                        else:

                            # info start file step
                            alg_logger.info(' ------> Read file "' + file_path_src_step +
                                            '" ... SKIPPED. File not available ')

                    # info end time step
                    alg_logger.info(' -----> Time subset "' + alg_time_step.strftime(time_format_algorithm) +
                                    '" ... DONE')

                else:

                    # info end time step
                    alg_logger.info(' -----> Time subset "' + alg_time_step.strftime(time_format_algorithm) +
                                    '" ... SKIPPED. Source datasets not available ')

            # check variable(s) source availability
            if vars_src_collection is not None:

                # sort time and attrs source
                time_src_collection.sort_index(inplace=True)
                attrs_src_collection.sort_index(inplace=True)

                # save variable(s) obj to ancillary file
                folder_name_anc_raw_step, file_name_anc_raw_step = os.path.split(file_path_anc_raw_step)
                make_folder(folder_name_anc_raw_step)

                obj_src_collection = {
                    'data': vars_src_collection, 'time': time_src_collection, 'attrs': attrs_src_collection}
                write_file_obj(file_path_anc_raw_step, obj_src_collection)

                # info end time reference (success)
                alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                                '" ... DONE')

            else:
                # info end time reference (failed)
                alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                                '" ... FAILED. Source datasets not available')
        else:

            # info end time step
            alg_logger.info(' -----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                            '" ... SKIPPED. Datasets previously saved.')

        # info end method
        alg_logger.info(' ---> Organize dynamic datasets ... DONE')

    # method to analyze data
    def analyze_data(self):

        # info start method
        alg_logger.info(' ---> Analyze dynamic datasets ... ')

        # get time reference
        alg_time_reference = self.alg_time_reference

        # get file path
        file_path_anc_raw_tmpl, file_path_anc_def_tmpl = self.file_path_anc_raw, self.file_path_anc_def
        # get grid info
        grid_geo_x_src, grid_geo_y_src = self.grid_geo_x_src, self.grid_geo_y_src
        grid_geo_x_dst, grid_geo_y_dst = self.grid_geo_x_dst, self.grid_geo_y_dst
        # get settings methods
        settings_resample_data = self.settings_resample_data
        settings_mask_data = self.settings_mask_data

        # info start time reference
        alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) + '" ... ')

        # method to fill the filename(s)
        file_path_anc_raw_step = fill_string_with_time(file_path_anc_raw_tmpl, alg_time_reference, self.alg_template)
        file_path_anc_def_step = fill_string_with_time(file_path_anc_def_tmpl, alg_time_reference, self.alg_template)

        # check file ancillary availability
        if not os.path.exists(file_path_anc_def_step):
            # check file source availability
            if os.path.exists(file_path_anc_raw_step):

                # info start get datasets
                alg_logger.info(' -----> (1) Get datasets ... ')
                # get datasets
                obj_collections_anc_raw_step = read_file_obj(file_path_anc_raw_step)
                # info end get datasets
                alg_logger.info(' -----> (1) Get datasets ... DONE')

                # info start adapt datasets
                alg_logger.info(' -----> (2) Adapt datasets ... ')
                obj_data_anc_adapt_step, obj_geo_x_adapt_step, obj_geo_y_adapt_step = adapt_data(
                    obj_collections_anc_raw_step, var_name_geo_x=geo_var_name_x, var_name_geo_y=geo_var_name_y)
                # info end adapt datasets
                alg_logger.info(' -----> (2) Adapt datasets ... DONE')

                # info start resample datasets
                alg_logger.info(' -----> (3) Resample datasets ... ')
                # resample datasets
                obj_data_anc_resample_step = resample_data(
                    obj_data_anc_adapt_step, obj_geo_x_adapt_step, obj_geo_y_adapt_step,
                    grid_geo_x_dst, grid_geo_y_dst, **settings_resample_data)
                # info end resample datasets
                alg_logger.info(' -----> (3) Resample datasets ... DONE')

                # info start mask datasets
                alg_logger.info(' -----> (4) Mask datasets ... ')
                # mask datasets
                obj_data_anc_mask_step = mask_data(obj_data_anc_resample_step, **settings_mask_data)
                # info end mask datasets
                alg_logger.info(' -----> (4) Mask datasets ... DONE')

                # info start resample datasets
                alg_logger.info(' -----> (5) Save datasets ... ')
                # save data in pickle format
                folder_name_anc_def_step, file_name_anc_def_step = os.path.split(file_path_anc_def_step)
                make_folder(folder_name_anc_def_step)
                write_file_obj(file_path_anc_def_step, obj_data_anc_mask_step)
                # info start resample datasets
                alg_logger.info(' -----> (5) Save datasets ... DONE')

                # info end time group
                alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                                '" ... DONE')

            else:
                # info end time group
                alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                                '" ... FAILED. Source datasets not available')

        else:
            # info end time group
            alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                            '" ... SKIPPED. Destination datasets previously computed')

        # info end method
        alg_logger.info(' ---> Analyze dynamic datasets ... DONE')

    # method to save data
    def dump_data(self):

        # info start method
        alg_logger.info(' ---> Dump dynamic datasets ... ')

        # get time reference
        alg_time_reference = self.alg_time_reference

        # get file path
        file_path_anc_def_tmpl, file_path_dst_tmpl = self.file_path_anc_def, self.file_path_dst
        # get grid info
        grid_geo_x_dst, grid_geo_y_dst = self.grid_geo_x_dst, self.grid_geo_y_dst
        transform_dst, proj_dst = self.transform_dst, self.proj_dst

        # info start time step
        alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) + '" ... ')

        # method to fill the filename(s)
        file_path_anc_def_step = fill_string_with_time(file_path_anc_def_tmpl, alg_time_reference, self.alg_template)
        file_path_dst_step = fill_string_with_time(file_path_dst_tmpl, alg_time_reference, self.alg_template)

        # check file destination availability
        if not os.path.exists(file_path_dst_step):
            # check file source availability
            if os.path.exists(file_path_anc_def_step):

                # method to get data obj
                variable_collection = read_file_obj(file_path_anc_def_step)

                # check destination format
                if self.format_dst == 'netcdf':
                    # method to organize netcdf dataset
                    variable_dset = organize_file_nc(
                        obj_variable=variable_collection, obj_time=alg_time_reference,
                        obj_geo_x=grid_geo_x_dst, obj_geo_y=grid_geo_y_dst,
                        obj_var_name=self.variables_dst)
                    # method to write netcdf dataset
                    folder_name_dst_step, file_name_dst_step = os.path.split(file_path_dst_step)
                    make_folder(folder_name_dst_step)
                    write_file_nc(file_path_dst_step, variable_dset)

                elif (self.format_dst == 'tiff') or (self.format_dst == 'tif'):
                    # method to organize tiff dataset
                    variable_data, variable_attrs = organize_file_tiff(
                        obj_variable=variable_collection, obj_time=alg_time_reference,
                        obj_geo_x=grid_geo_x_dst, obj_geo_y=grid_geo_y_dst, obj_var_name=self.variables_dst,
                        obj_transform=transform_dst, obj_proj=proj_dst)
                    # method to write tiff dataset
                    folder_name_dst_step, file_name_dst_step = os.path.split(file_path_dst_step)
                    make_folder(folder_name_dst_step)
                    write_file_tiff(
                        file_name=file_path_dst_step, file_data=variable_data,
                        **variable_attrs)

                else:
                    alg_logger.error(' ===> Destination format "' + self.format_dst + '" is not supported')
                    raise NotImplemented('Case not implemented yet')

                # info end time group
                alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                                '" ... DONE')
            else:
                # info end time group
                alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                                '" ... FAILED. Source datasets not available')

        else:
            # info end time group
            alg_logger.info(' ----> Time reference "' + alg_time_reference.strftime(time_format_algorithm) +
                            '" ... SKIPPED. Destination datasets previously computed')

        # info end method
        alg_logger.info(' ---> Dump dynamic datasets ... DONE')

# -------------------------------------------------------------------------------------
