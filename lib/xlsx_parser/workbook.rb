require 'tmpdir'

class Workbook
  class SheetNotFoundException < Exception ; end

  def initialize(filename)
    @tmpdir = Dir.mktmpdir
    extract_zip_content(filename)
    read_workbook
    parse_shared_strings
    @sheets = load_sheets
  end

  def sheets
    @sheet_names ||= @workbook_doc.
      xpath("//a:sheet", {"a" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}).
      collect do |sheet|
        sheet.attributes['name'].value
      end
  end

  # return a Sheet
  def sheet(sheet_name)
    raise SheetNotFoundException.new unless @sheets.include?(sheet_name)

    @sheets[sheet_name]
  end

private
  # reads the file representing the entire workbook
  # this is just a small file containing the sheet names
  def read_workbook
    @workbook_doc = Nokogiri::XML(File.read("#{@tmpdir}/workbook.xml"))
  end

  # read shared strings from xml file into an array of strings
  def parse_shared_strings
    doc = Nokogiri::XML(File.read("#{@tmpdir}/sharedStrings.xml"))
    elements = doc.xpath('//a:t', {"a" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main"})
    
    @shared_strings = elements.collect{|node| node.text}
    # release for gc
    elements = nil 
    #but return something excpected :)
    @shared_strings
  end


  def load_sheets
    ret = {}
    @sheet_files.each_with_index do |sheet_file, i|
      sheet_name = sheets[i]
      ret[sheet_name] = Sheet.new(sheet_name, sheet_file, @shared_strings)
    end
    
    ret
  end

  # parse an xml file and return a 2D 
  # array of the cells in an xlsx sheet
  def parse_sheet(sheet_file)
    xlsx_parser = XlsxSaxParser.new(@shared_strings)
    parser = Nokogiri::XML::SAX::Parser.new(xlsx_parser)
    parser.parse(File.read(sheet_file))
    xlsx_parser.doc
  end

  def extract_zip_content(zipfilename)
    Zip::ZipFile.open(zipfilename) do |zip|
      process_zipfile(zipfilename,zip)
    end
  end

  def process_zipfile(zipfilename, zip, path='')
    @sheet_files = []
    Zip::ZipFile.open(zipfilename) {|zf|
      zf.entries.each {|entry|
        #entry.extract
        if entry.to_s.end_with?('workbook.xml')
          open(@tmpdir+'/workbook.xml','wb') {|f|
            f << zip.read(entry)
          }
        end
        if entry.to_s.end_with?('sharedStrings.xml')
          open(@tmpdir+'/sharedStrings.xml','wb') {|f|
            f << zip.read(entry)
          }
        end
        if entry.to_s.end_with?('styles.xml')
          open(@tmpdir+'/styles.xml','wb') {|f|
            f << zip.read(entry)
          }
        end 
        if entry.to_s =~ /sheet([0-9]+).xml$/
          nr = $1
          open(@tmpdir+'/'+@file_nr.to_s+"sheet#{nr}.xml",'wb') {|f|
            f << zip.read(entry)
          }
          @sheet_files[nr.to_i-1] = @tmpdir+'/'+@file_nr.to_s+"sheet#{nr}.xml"
        end
      }
    }
    return
  end
end