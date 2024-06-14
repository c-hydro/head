"""
Class Features

Name:          drv_data_static
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20240606'
Version:       '1.0.0'
"""

# ----------------------------------------------------------------------------------------------------------------------
# libraries
import logging
import os

from lib_info_args import logger_name
from lib_data_io_geo import read_grid_data, create_grid_data

# set logger
alg_logger = logging.getLogger(logger_name)

# debug
# import matplotlib.pylab as plt
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# class driver data
class DrvData:

    # method to initialize class
    def __init__(self, alg_settings,
                 tag_section_flags='flags',
                 tag_section_datasets='datasets',
                 tag_section_log='log'):

        self.alg_flags = alg_settings[tag_section_flags]
        self.alg_datasets = alg_settings[tag_section_datasets]['static']
        self.alg_grid_source = self.alg_datasets['grid_source']
        self.alg_grid_destination = self.alg_datasets['grid_destination']
        self.alg_log = alg_settings[tag_section_log]

        # get geo grid source information
        self.folder_name_src = self.alg_grid_source['folder_name']
        self.file_name_src = self.alg_grid_source['file_name']
        if self.folder_name_src is not None and self.file_name_src is not None:
            self.file_path_src = os.path.join(self.folder_name_src, self.file_name_src)
        else:
            self.file_path_src = None

        # get geo grid destination information
        self.geo_x_corner_ll_dst = self.alg_grid_destination['geo_x_corner_ll']
        self.geo_x_corner_ur_dst = self.alg_grid_destination['geo_x_corner_ur']
        self.geo_y_corner_ll_dst = self.alg_grid_destination['geo_y_corner_ll']
        self.geo_y_corner_ur_dst = self.alg_grid_destination['geo_y_corner_ur']
        self.geo_x_res_dst = self.alg_grid_destination['geo_x_res']
        self.geo_y_res_dst = self.alg_grid_destination['geo_y_res']

    # method to organize data
    def organize_data(self):

        # info start method
        alg_logger.info(' ---> Organize static datasets ... ')

        # define source grid
        if self.file_path_src is not None:
            geo_x_grid_src, geo_y_grid_src = read_grid_data(self.file_path_src)
        else:
            geo_x_grid_src, geo_y_grid_src = None, None

        # define destination grid
        geo_x_grid_dst, geo_y_grid_dst, geo_x_min_dst, geo_x_max_dst, geo_y_min_dst, geo_y_max_dst = create_grid_data(
            self.geo_x_corner_ll_dst, self.geo_x_corner_ur_dst, self.geo_y_corner_ll_dst, self.geo_y_corner_ur_dst,
            self.geo_x_res_dst, self.geo_y_res_dst)

        # organize grid obj
        grid_obj = {
            'grid_geo_x_src': geo_x_grid_src, 'grid_geo_y_src': geo_y_grid_src,
            'grid_geo_x_dst': geo_x_grid_dst, 'grid_geo_y_dst': geo_y_grid_dst,
            'grid_geo_x_min_dst': geo_x_min_dst, 'grid_geo_x_max_dst': geo_x_max_dst,
            'grid_geo_y_min_dst': geo_y_min_dst, 'grid_geo_y_max_dst': geo_y_max_dst,
            'transform_src': None, 'proj_src': None,
            'transform_dst': None, 'proj_dst': None}

        # info end method
        alg_logger.info(' ---> Organize static datasets ... DONE')

        return grid_obj

    # ------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
