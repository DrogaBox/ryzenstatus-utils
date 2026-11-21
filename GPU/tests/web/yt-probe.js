/**
 * @fileoverview Console probe of YouTube codec answers and AV1 experiment
 * flags.
 *
 * Paste into Safari Web Inspector on a youtube.com/watch page.
 */

(async () => {
  'use strict';

  const rows = [];

  /**
   * @param {string} type MIME type to test with MediaSource.
   * @return {boolean|string}
   */
  const isTypeSupported = (type) => {
    try {
      return MediaSource.isTypeSupported(type);
    } catch (error) {
      return 'ERR ' + error;
    }
  };

  const types = [
    'video/mp4; codecs="av01.0.05M.08"',
    'video/mp4; codecs="av01.0.12M.08"; width=3840; height=2160; framerate=60',
    'video/mp4; codecs="av01.0.13M.08"; width=3840; height=2160; framerate=60; bitrate=20000000',
    'video/mp4; codecs="av01.0.16M.08"; width=7680; height=4320; framerate=60',
    'video/mp4; codecs="av01.0.13M.10.0.110.09.16.09.0"',
    'video/mp4; codecs="av01.0.13M.10"; eotf=smpte2084',
    'video/webm; codecs="vp9"; width=3840; height=2160; framerate=60',
    'video/webm; codecs="vp09.02.51.10.01.09.16.09.00"',
  ];

  for (const type of types) {
    rows.push(['MSE', type, isTypeSupported(type)]);
  }

  rows.push([
    'canPlayType av01',
    '',
    document.createElement('video').canPlayType(
        'video/mp4; codecs="av01.0.05M.08"'),
  ]);

  const flags = (window.yt && yt.config_ && yt.config_.EXPERIMENT_FLAGS) ||
      (window.ytcfg && ytcfg.get && ytcfg.get('EXPERIMENT_FLAGS')) || {};
  for (const [key, value] of Object.entries(flags)) {
    if (/av1|av01|dav1d/i.test(key)) {
      rows.push(['flag', key, String(value)]);
    }
  }

  try {
    const player = document.querySelector('#movie_player');
    const playerResponse = window.ytInitialPlayerResponse ||
        (player && player.getPlayerResponse && player.getPlayerResponse());
    const formats = (playerResponse && playerResponse.streamingData &&
                     playerResponse.streamingData.adaptiveFormats) ||
        [];
    const av1 = formats.filter((format) => /av01/.test(format.mimeType))
                    .map((format) => format.qualityLabel);
    const vp9 = formats.filter((format) => /vp09|vp9/.test(format.mimeType))
                    .map((format) => format.qualityLabel);
    rows.push([
      'formats in player response',
      'AV1: ' + (av1.join(',') || 'none'),
      'VP9: ' + (vp9.join(',') || 'none'),
    ]);
  } catch (error) {
    rows.push(['formats', '', 'ERR ' + error]);
  }

  try {
    rows.push([
      'localStorage yt-player-av1-pref',
      '',
      localStorage.getItem('yt-player-av1-pref'),
    ]);
  } catch (error) {
    // localStorage can throw in a sandboxed inspector context.
  }

  rows.push([
    'cookie PREF',
    '',
    (document.cookie.match(/PREF=[^;]*/) || ['none'])[0],
  ]);

  console.table(rows);
  return rows.map((row) => row.join(' | ')).join('\n');
})();
