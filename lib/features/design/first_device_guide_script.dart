/// Passes only the minimum visibility bit to the packaged Dashboard.
String buildFirstDeviceGuideScript(bool visible) =>
    '''
  (() => {
    const guide = document.getElementById('el-first-device-guide');
    if (!guide) return;
    guide.hidden = ${visible ? 'false' : 'true'};
    guide.style.display = ${visible ? "''" : "'none'"};
  })();
''';
