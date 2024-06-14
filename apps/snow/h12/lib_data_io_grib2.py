"""
Library Features:

Name:          lib_data_io_grib2
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20230727'
Version:       '1.0.0'
"""

# ----------------------------------------------------------------------------------------------------------------------
# libraries
import logging
import os
import numpy as np
import xarray as xr
import pygrib

from copy import deepcopy

from lib_info_args import logger_name
from lib_utils_generic import search_key_by_value

# set logger
alg_logger = logging.getLogger(logger_name)

# debug
import matplotlib.pylab as plt
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to read grib2 file
def read_file_grib2(file_name, file_variables=None,
                    var_name_geo_x='longitude', var_name_geo_y='latitude'):

    # check file availability
    if os.path.exists(file_name):

        # open file
        file_dset = pygrib.open(file_name)
        # get number of messages
        file_messages_n = file_dset.messages
        file_message_arr = np.linspace(1, file_messages_n, file_messages_n, endpoint=True, dtype=int)

        # iterate over messages
        data_obj, geo_obj, change_orientation = {}, {}, False
        for file_messages_i in file_message_arr:

            # get message object and name
            file_message_obj = file_dset[int(file_messages_i)]
            file_message_name = file_message_obj.name

            # check message name in expected variables list
            if file_message_name in list(file_variables.values()):

                # get data and geographical coordinates (one step)
                # file_data, file_geo_y, file_geo_x = file_message_obj.data()

                # get data and geographical coordinates (split)
                file_data = file_message_obj.values

                if (var_name_geo_x not in list(geo_obj.keys())) or (var_name_geo_y not in list(geo_obj.keys())):
                    file_geo_y_grid, file_geo_x_grid = file_message_obj.latlons()
                    file_geo_y_ll, file_geo_y_ul = file_geo_y_grid[-1, 0], file_geo_y_grid[0, 0]

                    ''' debug
                    plt.figure()
                    plt.imshow(file_data)
                    plt.colorbar()
                    plt.figure()
                    plt.imshow(file_geo_y_grid)
                    plt.colorbar()
                    plt.figure()
                    plt.imshow(file_geo_x_grid)
                    plt.colorbar()
                    plt.show()
                    '''

                    if file_geo_y_ll > file_geo_y_ul:
                        file_geo_y_grid = np.flipud(file_geo_y_grid)
                        change_orientation = True

                    # select the unique geo arrays
                    file_geo_y_arr, file_geo_x_arr = file_geo_y_grid[:, 0], file_geo_x_grid[0, :]

                else:
                    file_geo_y_grid, file_geo_x_grid = None, None

                if change_orientation:
                    file_data = np.flipud(file_data)

                # select variable name in and out
                var_name_in = deepcopy(file_message_name)
                var_name_out = search_key_by_value(file_variables, var_name_in)[0]

                # save geographical coordinates
                if var_name_geo_x not in list(geo_obj.keys()):
                    geo_obj[var_name_geo_x] = {}
                    geo_obj[var_name_geo_x] = file_geo_x_grid
                if var_name_geo_y not in list(geo_obj.keys()):
                    geo_obj[var_name_geo_y] = {}
                    geo_obj[var_name_geo_y] = file_geo_y_grid
                # save data
                data_obj[var_name_out] = {}
                data_obj[var_name_out] = file_data

        return data_obj, geo_obj

# ----------------------------------------------------------------------------------------------------------------------
