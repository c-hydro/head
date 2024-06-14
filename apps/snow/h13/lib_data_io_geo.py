"""
Library Features:

Name:          lib_data_io_geo
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20230307'
Version:       '1.0.0'
"""
# ----------------------------------------------------------------------------------------------------------------------
# Library
import logging
import os

import numpy as np
import xarray as xr

from lib_info_args import logger_name


# set logger
alg_logger = logging.getLogger(logger_name)

# logging
logging.getLogger('rasterio').setLevel(logging.WARNING)

# debug
# import matplotlib.pylab as plt
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to create grid data
def create_grid_data(geo_x_min, geo_x_max, geo_y_min, geo_y_max, geo_x_res, geo_y_res):

    geo_x_arr = np.arange(geo_x_min, geo_x_max + np.abs(geo_x_res / 2), np.abs(geo_x_res), float)
    geo_y_arr = np.flip(np.arange(geo_y_min, geo_y_max + np.abs(geo_y_res / 2), np.abs(geo_y_res), float), axis=0)
    geo_x_grid, geo_y_grid = np.meshgrid(geo_x_arr, geo_y_arr)

    geo_x_min_round, geo_x_max_round = round(np.min(geo_x_grid), 7), round(np.max(geo_x_grid), 7)
    geo_y_min_round, geo_y_max_round = round(np.min(geo_y_grid), 7), round(np.max(geo_y_grid), 7)

    return geo_x_grid, geo_y_grid, geo_x_min_round, geo_x_max_round, geo_y_min_round, geo_y_max_round
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to read grid data
def read_grid_data(file_name):

    # open file
    if os.path.exists(file_name):
        file_dset = xr.open_dataset(file_name)
        file_geo_x = file_dset.variables['long'].values
        file_geo_y = file_dset.variables['latg'].values
    else:
        alg_logger.error(' ===> File static source grid "' + file_name + '" is not available')
        raise FileNotFoundError('File is mandatory to correctly run the algorithm')

    return file_geo_x, file_geo_y
# ----------------------------------------------------------------------------------------------------------------------
