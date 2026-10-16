import unittest
import xml.etree.ElementTree as ET
from package_store import manifest, FOUNDATION, RESCAP

class StorePackageTests(unittest.TestCase):
    def test_identity_and_version_are_exact_and_xml_escaped(self):
        identity={'name': 'Tableo.Fixture', 'publisher': 'CN=Fixture & Test',
                  'publisherDisplayName': 'Fixture & Test', 'displayName': 'Tableo'}
        root=ET.fromstring(manifest(identity, '1.2.0'))
        value=root.find('{'+FOUNDATION+'}Identity')
        self.assertEqual(value.attrib['Publisher'],identity['publisher'])
        self.assertEqual(value.attrib['Version'],'1.2.0.0')
        self.assertEqual(value.attrib['ProcessorArchitecture'],'x64')
        capability=root.find('.//{'+RESCAP+'}Capability')
        self.assertEqual(capability.attrib['Name'],'runFullTrust')
    def test_missing_identity_or_invalid_version_is_rejected(self):
        identity={'name': 'Tableo.Fixture','publisher':'CN=Fixture','publisherDisplayName':'Fixture'}
        for key in ['name','publisher','publisherDisplayName']:
            with self.subTest(key=key),self.assertRaises(ValueError):
                manifest({**identity,key:''},'1.2.0')
        with self.assertRaises(ValueError):manifest(identity,'1.2.0+46')

if __name__=='__main__': unittest.main()
