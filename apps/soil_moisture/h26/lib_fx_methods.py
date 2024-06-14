"""
Library Features:

Name:          lib_fx_utils
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20230727'
Version:       '1.0.0'
"""

# ----------------------------------------------------------------------------------------------------------------------
# libraries
import logging

import numpy as np
import pandas as pd

from copy import deepcopy

from lib_utils_geo import resample_points_to_grid
from lib_info_args import logger_name

# set logger
alg_logger = logging.getLogger(logger_name)

# debug
import matplotlib.pylab as plt
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to adapt data
def adapt_data(obj_data_src, var_name_geo_x='longitude', var_name_geo_y='latitude',):

    # adapt geographical values x
    if var_name_geo_x in list(obj_data_src.keys()):
        geo_x_values_dst = obj_data_src[var_name_geo_x].values
        obj_data_src.pop(var_name_geo_x)
    else:
        alg_logger.error(' ===> Geographical variable "' + var_name_geo_x + '" is not available in the datasets')
        raise RuntimeError('Geographical variable is needed by the method')
    # adapt geographical values y
    if var_name_geo_y in list(obj_data_src.keys()):
        geo_y_values_dst = obj_data_src[var_name_geo_y].values
        obj_data_src.pop(var_name_geo_y)
    else:
        alg_logger.error(' ===> Geographical variable "' + var_name_geo_y + '" is not available in the datasets')
        raise RuntimeError('Geographical variable is needed by the method')

    # adapt variable data
    obj_data_dst = {}
    for var_name, var_data_src in obj_data_src.items():
        var_values_src = var_data_src.values
        obj_data_dst[var_name] = var_values_src

    return obj_data_dst, geo_x_values_dst, geo_y_values_dst
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to resample data
def resample_data(obj_data_src, geo_x_values_src, geo_y_values_src, geo_x_values_dst, geo_y_values_dst, **kwargs):

    # iterate over variable(s)
    obj_data_dst = {}
    for var_name, var_values_src in obj_data_src.items():
        if var_values_src is not None:

            if var_name in kwargs:
                var_settings = kwargs.get(var_name)
            else:
                var_settings = {}

            var_values_dst, _, _ = resample_points_to_grid(
                var_values_src, geo_x_values_src, geo_y_values_src, geo_x_values_dst, geo_y_values_dst, **var_settings)

            var_values_dst = np.flipud(var_values_dst)

            obj_data_dst[var_name] = var_values_dst
        else:
            alg_logger.warning(' ===> Data "' + var_name + '" is not available in the datasets')
            obj_data_dst[var_name] = None

        ''' debug
        plt.figure()
        plt.imshow(var_values_dst)
        plt.colorbar()
        plt.show()
        plt.figure()
        plt.imshow(geo_y_values_dst)
        plt.colorbar()
        plt.show()
        '''

    return obj_data_dst
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to apply settings to data
def apply_settings(var_data, var_settings):

    var_fill_data = None
    if 'fill_data' in list(var_settings.keys()):
        var_fill_data = var_settings['fill_data']
    if var_fill_data is None:
        var_fill_data = np.nan
    var_type_in = None
    if 'type_in' in list(var_settings.keys()):
        var_type_in = var_settings['type_in']
    if var_type_in is None:
        var_type_in = 'float'
    var_type_out = None
    if 'type_out' in list(var_settings.keys()):
        var_type_out = var_settings['type_out']
    if var_type_out is None:
        var_type_out = 'float'
    if var_type_in != var_type_out:
        var_data = var_data.astype(var_type_out)

    if 'no_data' in list(var_settings.keys()):
        var_no_data = var_settings['no_data']
        if var_no_data is not None:
            var_data[var_data == var_no_data] = var_fill_data

    if 'scale_factor' in list(var_settings.keys()):
        var_scale_factor = var_settings['scale_factor']
        if var_scale_factor is not None:
            var_data = var_data / var_scale_factor

    if 'min_value' in list(var_settings.keys()):
        var_min_value = var_settings['min_value']
        if var_min_value is not None:
            var_data[var_data < var_min_value] = var_fill_data

    if 'max_value' in list(var_settings.keys()):
        var_max_value = var_settings['max_value']
        if var_max_value is not None:
            var_data[var_data > var_max_value] = var_fill_data

    if ('mask_in' in list(var_settings.keys())) and ('mask_out' in list(var_settings.keys())):
        var_mask_in, var_mask_out = var_settings['mask_in'], var_settings['mask_out']
        var_data_tmp = deepcopy(var_data)
        if var_mask_in is not None and var_mask_out is not None:
            for value_in, value_out in zip(var_mask_in, var_mask_out):

                if isinstance(value_in, list) and isinstance(value_out, list):
                    pass  # nothing to do if the input and output values are lists
                else:
                    var_data[var_data_tmp == value_in] = value_out

    return var_data
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to organize data
def organize_data(obj_data, obj_geo,
                  var_name_geo_x='longitude', var_name_geo_y='latitude', **kwargs):

    # get geo information
    n_data = None
    variable_geo = {}
    for var_name, var_data in obj_geo.items():
        if n_data is None:
            n_data = var_data.flatten().shape[0]

        if var_name in kwargs:
            var_settings = kwargs.get(var_name)
        else:
            var_settings = {}

        var_data_tmp = deepcopy(var_data.flatten())
        var_data_def = apply_settings(var_data_tmp, var_settings)

        variable_geo[var_name] = var_data_def

    # define variable obj
    variable_data = {}
    for var_name, var_data in obj_data.items():

        if var_name in kwargs:
            var_settings = kwargs.get(var_name)
        else:
            var_settings = {}

        if var_data is None:
            var_data = np.zeros((n_data, 1))
            var_data[:] = np.nan
            alg_logger.warning(' ===> Data "' + var_name + '" is not available in the datasets')
        else:

            ''' debug
            plt.figure()
            plt.imshow(var_data.astype(float))
            plt.colorbar()
            plt.show()
            '''
            var_data = var_data.flatten()

        var_data_tmp = deepcopy(var_data)
        var_data_def = apply_settings(var_data_tmp, var_settings)

        variable_data[var_name] = var_data_def

    # define variable collections
    variable_collections = {**variable_data, **variable_geo}

    # define variable data frame
    variable_dframe = pd.DataFrame(data=variable_collections)
    variable_dframe = variable_dframe.dropna(axis=0, how='any', subset=[var_name_geo_x, var_name_geo_y])
    variable_dframe.reset_index(drop=True, inplace=True)

    return variable_dframe

# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to mask data
def mask_data(obj_data_src, **kwargs):

    # iterate over variable(s)
    obj_data_dst = {}
    for var_name, var_data_src in obj_data_src.items():
        if var_data_src is not None:
            if var_name in kwargs:
                var_settings = kwargs.get(var_name)
            else:
                var_settings = {}

            # get variable data
            var_data_dst = deepcopy(var_data_src)

            # get no data value
            var_no_data = np.nan
            if 'no_data' in var_settings:
                var_no_data = var_settings['no_data']
                if var_no_data is None:
                    var_no_data = np.nan
            # apply mask of min values
            if 'var_min' in var_settings:
                var_min = var_settings['var_min']
                if var_min is not None:
                    var_data_dst[var_data_dst < var_min] = var_no_data
            # apply mask of max values
            if 'var_max' in var_settings:
                var_max = var_settings['var_max']
                if var_max is not None:
                    var_data_dst[var_data_dst > var_max] = var_no_data
            # store data in a collection
            obj_data_dst[var_name] = var_data_dst

            ''' debug
            plt.figure()
            plt.imshow(var_data_dst)
            plt.colorbar()
            plt.show()
            '''

        else:
            alg_logger.warning(' ===> Data "' + var_name + '" is not available in the datasets')
            obj_data_dst[var_name] = None

    return obj_data_dst
# ----------------------------------------------------------------------------------------------------------------------
