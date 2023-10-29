import fitz  # PyMuPDF

pdf_path = 'your-pdf-file.pdf'

# Open the PDF file
pdf_document = fitz.open(pdf_path)

# Get the bookmarks
bookmarks = pdf_document.get_outline()

# Print the bookmarks (outline)
def print_bookmarks(bookmark_list, level=0):
    for bookmark in bookmark_list:
        print("\t" * level + bookmark[1])
        if bookmark[2]:
            print_bookmarks(bookmark[2], level + 1)

print_bookmarks(bookmarks)

