class readlist:
    def __init__(self, file_path):
        self.file_path = file_path
        self.data = []

    def readfile(self):
        try:
            with open(self.file_path, 'r') as file:
                for line in file:
                    self.data.append(line.strip())

        except FileNotFoundError:
            print(f"File not found: {self.file_path}")
        except Exception as e:
            print(f"An error occurred: {str(e)}")

    def printline(self):
        for item in self.data :
            print (item)

    def getlines(self):
        return self.data 