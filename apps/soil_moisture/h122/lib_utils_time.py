"""
Library Features:

Name:          lib_utils_time
Author(s):     Fabio Delogu (fabio.delogu@cimafoundation.org)
Date:          '20230830'
Version:       '1.0.0'
"""

# ----------------------------------------------------------------------------------------------------------------------
# libraries
import logging
import pandas as pd

from copy import deepcopy
from datetime import date

from lib_info_args import logger_name

# set logger
alg_logger = logging.getLogger(logger_name)
# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# method to set time file
def set_time_file(time_start=None, time_end=None,
                  time_frequency='H', time_rounding='D', time_period=0, time_reverse=True):

    if (time_start is None) and (time_end is None):
        alg_logger.error(' ===> Variable "time_start" and "time_end" are defined by NoneType')
        raise RuntimeError('Variable "time_start" and/or "time_end" must be defined to get correctly time(s)')

    if time_start is not None:
        time_start = time_start.round(time_rounding)
    if time_end is not None:
        time_end = time_end.round(time_rounding)

    if time_frequency == 'D':
        if time_start is None:
            time_start = deepcopy(time_end.replace(hour=0, minute=0, second=0))
        if time_end is None:
            time_end = deepcopy(time_start.replace(hour=23, minute=59, second=59))
    elif time_frequency == 'H':
        if time_start is None:
            time_start = deepcopy(time_end.replace(minute=0, second=0))
        if time_end is None:
            time_end = deepcopy(time_start.replace(minute=59, second=59))
    else:
        alg_logger.error(' ===> Time frequency "' + time_frequency + '" is not supported')
        raise NotImplemented('Case not implemented yet')

    time_range = pd.date_range(start=time_start, end=time_end, freq=time_frequency)

    if time_reverse:
        time_range = time_range[::-1]

    return time_range

# ----------------------------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------------------------
# Method to set time info
def set_time_info(time_run_args=None, time_run_file=None, time_format='%Y-%m-%d %H:$M',
                  time_run_file_start=None, time_run_file_end=None,
                  time_period=1, time_frequency='H', time_rounding='H', time_reverse=True,
                  time_rounding_chunks='1H', time_frequency_chunks='12H'):

    alg_logger.info(' ----> Set time info ... ')
    if (time_run_file_start is None) and (time_run_file_end is None):

        alg_logger.info(' -----> Time info defined by "time_run" argument ... ')

        if time_run_args is not None:
            time_run = time_run_args
            alg_logger.info(' ------> Time ' + time_run + ' set by argument')
        elif (time_run_args is None) and (time_run_file is not None):
            time_run = time_run_file
            alg_logger.info(' ------> Time ' + time_run + ' set by user')
        elif (time_run_args is None) and (time_run_file is None):
            time_now = date.today()
            time_run = time_now.strftime(time_format)
            alg_logger.info(' ------> Time ' + time_run + ' set by system')
        else:
            alg_logger.info(' ----> Set time info ... FAILED')
            alg_logger.error(' ===> Argument "time_run" is not correctly set')
            raise IOError('Time type or format is wrong')

        time_df = pd.DataFrame([{'time_run': pd.Timestamp(time_run)}])
        time_df['time_round'] = time_df['time_run'].dt.floor(time_rounding)

        time_run_round = time_df['time_round'].values[0]
        time_run_day = pd.Timestamp(time_df['time_round'].dt.floor('1D').values[0])

        if time_period == 1:
            time_period = 2

        if time_period > 0:
            time_range = pd.date_range(end=time_run_round, periods=time_period, freq=time_frequency)
        else:
            alg_logger.warning(' ===> TimePeriod must be greater then 0. TimePeriod is set automatically to 1')
            time_range = pd.DatetimeIndex([time_run_round], freq=time_frequency)

        alg_logger.info(' -----> Time info defined by "time_run" argument ... DONE')

    elif (time_run_file_start is not None) and (time_run_file_end is not None):

        alg_logger.info(' -----> Time info defined by "time_start" and "time_end" arguments ... ')

        time_run_file_start = pd.Timestamp(time_run_file_start)
        time_run_file_start = time_run_file_start.floor(time_rounding)
        time_run_file_end = pd.Timestamp(time_run_file_end)
        time_run_file_end = time_run_file_end.floor(time_rounding)

        time_now = date.today()
        time_run = time_now.strftime(time_format)
        time_run_round = pd.Timestamp(time_run)
        time_run_day = time_run.floor(time_rounding).dt.floor(time_rounding)
        time_range = pd.date_range(start=time_run_file_start, end=time_run_file_end, freq=time_frequency)

        alg_logger.info(' -----> Time info defined by "time_start" and "time_end" arguments ... DONE')

    else:
        alg_logger.info(' ----> Set time info ... FAILED')
        alg_logger.error(' ===> Arguments "time_start" and/or "time_end" is/are not correctly set')
        raise IOError('Time type or format is wrong')

    # arrange time range
    if time_run_round not in time_range:
        time_range = time_range.insert(0, time_run_round)
    time_range = time_range.sort_values()

    time_range_chunks = pd.date_range(start=time_range[0], end=time_range[-1], freq=time_frequency_chunks)

    # apply time reverse
    if time_reverse:
        time_range = time_range[::-1]

    # define time chunks
    time_chunks = {}
    for time_id, time_step_start in enumerate(time_range[1:]):

        time_reference = deepcopy(time_range[time_id])
        time_step_end = time_range[time_id] - pd.Timedelta(time_rounding_chunks)
        time_step_range = pd.date_range(start=time_step_start, end=time_step_end, freq=time_rounding_chunks)

        time_chunks[time_reference] = time_step_range

    alg_logger.info(' ----> Set time info ... DONE')

    return time_run, time_range_chunks, time_chunks

# ----------------------------------------------------------------------------------------------------------------------
