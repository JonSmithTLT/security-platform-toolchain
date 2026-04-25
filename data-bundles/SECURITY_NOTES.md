# Data Bundle Security Notes

The data bundle may contain AV/DLP-sensitive advisory and intelligence text from
upstream public datasets. This can include PoC strings, exploit commands,
webshell snippets, RCE examples, suspicious indicators, and scanner fixtures.

The bundle is not intended to contain live malware samples, real credentials,
proprietary target data, customer source code, or private incident data.

Use the full data bundle for maximum offline vulnerability and intelligence
coverage. Use a sanitized bundle variant when an environment cannot accept
PoC/exploit-heavy advisory text.

Known sensitive sources include GitHub Advisory Database, NVD/CVE records,
YARA rules, threat-intelligence feeds, and vendor advisories.

