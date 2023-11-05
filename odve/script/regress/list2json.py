import json

class list2json:
    def __init__(self):
        self.data = {}

    def convert2j (self, list):
        for line in list :
            parts = line.split(":")
            self.data[parts[0]] = {"cmd" : parts[1]} 
        return self.data  
    
    def gencmd (self, data):
        cmds = []
        for run in data :
            cmd=f'make run RUN_DIR={run} {data[run]["cmd"]}'
            cmds.append(cmd)
        return cmds  
    