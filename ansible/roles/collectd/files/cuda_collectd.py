#!/usr/bin/env python

# Type needs to exist in: /usr/share/collectd/types.db

import collectd
import subprocess
import xml.etree.ElementTree as ET

def read(data=None):
        vl = collectd.Values(type='gauge')
        vl.plugin = 'cuda'

        out = subprocess.check_output(['nvidia-smi', '-q', '-x'])
        root = ET.fromstring(out)

        for gpu in root.iter('gpu'):
                vl.plugin_instance = '%s' % (gpu.attrib['id'])

		if not isinstance(gpu.find('fan_speed').text.split()[0], str):
			vl.dispatch(type='fanspeed',
				    values=[float(gpu.find('fan_speed').text.split()[0])])

                vl.dispatch(type='temperature',
                            values=[float(gpu.find('temperature/gpu_temp').text.split()[0])])

                vl.dispatch(type='memory', type_instance='used',
                            values=[1e6 * float(gpu.find('fb_memory_usage/used').text.split()[0])])

                vl.dispatch(type='memory', type_instance='total',
                            values=[1e6 * float(gpu.find('fb_memory_usage/total').text.split()[0])])

                vl.dispatch(type='percent', type_instance='gpu_util',
                            values=[float(gpu.find('utilization/gpu_util').text.split()[0])])

                vl.dispatch(type='percent', type_instance='mem_util',
                            values=[float(gpu.find('utilization/memory_util').text.split()[0])])

                vl.dispatch(type='power', type_instance='draw',
                            values=[float(gpu.find('power_readings/power_draw').text.split()[0])])

                vl.dispatch(type='frequency', type_instance='graphics_clock',
                            values=[float(gpu.find('clocks/graphics_clock').text.split()[0])])

                vl.dispatch(type='frequency', type_instance='mem_clock',
                            values=[float(gpu.find('clocks/mem_clock').text.split()[0])])

		if not isinstance(gpu.find('fan_speed').text.split()[0], str):
			vl.dispatch(type='bytes', type_instance='tx',
				    values=[float(gpu.find('pci/tx_util').text.split()[0])])

		if not isinstance(gpu.find('fan_speed').text.split()[0], str):
			vl.dispatch(type='bytes', type_instance='rx',
				    values=[float(gpu.find('pci/rx_util').text.split()[0])])

collectd.register_read(read)
