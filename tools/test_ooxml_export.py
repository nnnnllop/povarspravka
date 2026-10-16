import unittest
import xml.etree.ElementTree as ET
import zipfile
import io

class TestExportGeneration(unittest.TestCase):
    def test_docx_xml_validity(self):
        # Sample document.xml template with Cyrillic
        doc_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="28"/></w:rPr>
        <w:t>Расчет пищевой и энергетической ценности блюда: Борщ</w:t>
      </w:r>
    </w:p>
    <w:tbl>
      <w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>Картофель</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>150.0</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
  </w:body>
</w:document>"""
        root = ET.fromstring(doc_xml)
        self.assertIn('document', root.tag)

    def test_xlsx_xml_validity(self):
        sheet_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" s="0" t="inlineStr"><is><t>№</t></is></c>
      <c r="B1" s="0" t="inlineStr"><is><t>Картофель</t></is></c>
      <c r="C1" s="0"><v>150.0</v></c>
    </row>
  </sheetData>
</worksheet>"""
        root = ET.fromstring(sheet_xml)
        self.assertIn('worksheet', root.tag)

if __name__ == '__main__':
    unittest.main()
