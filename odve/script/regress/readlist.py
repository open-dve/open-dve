class readlist:
    def __init__(self, file_path):
        self.file_path = file_path
        self.data = []

    def readfile(self):
        """Keep the meaningful lines of a .list file: blanks and '#' comments are dropped."""
        try:
            with open(self.file_path, 'r') as file:
                for line in file:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        self.data.append(line)

        except FileNotFoundError:
            print(f"File not found: {self.file_path}")
            exit (1)
        except Exception as e:
            print(f"An error occurred: {str(e)}")
            exit (1)
    def printline(self):
        for item in self.data :
            print (item)

    def getlines(self):
        return self.data
