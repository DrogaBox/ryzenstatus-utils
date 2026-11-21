// ==UserScript==
// @name         YouTube: prefer AV1 over VP9
// @description  Reports VP9 as not smooth / not power-efficient in Media Capabilities, the way Safari does on Macs without VP9 hardware, so YouTube picks AV1 (hardware-decoded through the AMD VCN VideoToolbox plugin) when a video has it. VP9 stays supported, so videos without AV1 still play VP9 up to 4K.
// @version      2.0
// @match        https://www.youtube.com/*
// @match        https://m.youtube.com/*
// @match        https://www.youtube-nocookie.com/*
// @run-at       document-start
// @inject-into  page
// @grant        none
// ==/UserScript==

/**
 * @fileoverview Reports VP9 as not power-efficient so YouTube prefers AV1.
 *
 * Do not hide VP9 from MediaSource.isTypeSupported: YouTube sends that
 * answer to the server as devicePlaybackCapabilities.supportsVp9Encoding,
 * and with false the server drops AV1 too (H.264 only).
 */

(() => {
  'use strict';

  /**
   * @param {?string|undefined} contentType MIME type from mediaCapabilities.
   * @return {boolean}
   */
  const isVp9 = (contentType) => /vp0?9/i.test(String(contentType || ''));

  const mediaCapabilities = navigator.mediaCapabilities;
  if (!mediaCapabilities || !mediaCapabilities.decodingInfo) {
    return;
  }

  const originalDecodingInfo =
      mediaCapabilities.decodingInfo.bind(mediaCapabilities);

  /**
   * @param {!MediaDecodingConfiguration} configuration
   * @return {!Promise<!MediaCapabilitiesDecodingInfo>}
   */
  mediaCapabilities.decodingInfo = async (configuration) => {
    const info = await originalDecodingInfo(configuration);
    if (configuration && configuration.video &&
        isVp9(configuration.video.contentType) && info && info.supported) {
      return {
        supported: true,
        smooth: false,
        powerEfficient: false,
        configuration: info.configuration,
      };
    }
    return info;
  };

  console.debug('[prefer-av1] VP9 reported as not power-efficient');
})();
