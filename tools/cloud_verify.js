// 双云本地连接验证脚本（缤纷云 S3 + 坚果云 WebDAV）
// 凭据一律走环境变量，本脚本不含任何密钥，可安全入库。
//
// 用法（PowerShell，把值换成你自己的）：
//   $env:LH_S3_AK='<AccessKey>'; $env:LH_S3_SK='<SecretKey>'; $env:LH_S3_BUCKET='qoderwork'
//   $env:LH_WD_USER='你的邮箱'; $env:LH_WD_PASS='坚果云应用密码'
//   node tools/cloud_verify.js
//
// 输出判读：
//   S3 五个探针若「V2 虚拟主机式」400 而「V1/路径式」200 → App 需换探针口径（把结果发回来）；
//   五个全 4xx → 桶名/子账户桶权限问题（缤纷云控制台→子账户→分配桶权限）；
//   WebDAV 链 PROPFIND(404或207)→MKCOL→PUT→LIST→DELETE 全绿 → 坚果云同步链路通。
'use strict';
const crypto = require('crypto');
const https = require('https');


const S3_HOST = 's3.bitiful.net';
const S3_REGION = 'cn-east-1';


// 环境变量缺失时回落读本地凭据文件 tools/.cloud_verify.env（已 .gitignore，
// 永不入库；agent 只执行本脚本、不读该文件内容）。格式：每行 KEY=VALUE。
if (!process.env.LH_S3_AK || !process.env.LH_S3_SK || !process.env.LH_WD_USER || !process.env.LH_WD_PASS) {
  try {
    const fs = require('fs');
    const txt = fs.readFileSync(__dirname + '/.cloud_verify.env', 'utf8');
    const get = (k) => (txt.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1] || '';
    if (!process.env.LH_S3_AK) process.env.LH_S3_AK = get('LH_S3_AK');
    if (!process.env.LH_S3_SK) process.env.LH_S3_SK = get('LH_S3_SK');
    if (!process.env.LH_WD_USER) process.env.LH_WD_USER = get('LH_WD_USER');
    if (!process.env.LH_WD_PASS) process.env.LH_WD_PASS = get('LH_WD_PASS');
    if (!process.env.LH_S3_BUCKET) process.env.LH_S3_BUCKET = get('LH_S3_BUCKET') || 'qoderwork';
    if (!process.env.LH_WD_DIR) process.env.LH_WD_DIR = get('LH_WD_DIR') || 'qoderwork';
  } catch (_) {
    /* 无本地文件则维持原报错 */
  }
}
const AK = process.env.LH_S3_AK || '';
const SK = process.env.LH_S3_SK || '';
const WU = process.env.LH_WD_USER || '';
const WP = process.env.LH_WD_PASS || '';
const S3_BUCKET = process.env.LH_S3_BUCKET || 'qoderwork';
const WD_DIR = process.env.LH_WD_DIR || 'qoderwork';

if (!AK || !SK || !WU || !WP) {
  console.error('缺少凭据：设环境变量 LH_S3_AK/LH_S3_SK/LH_WD_USER/LH_WD_PASS，'
      + '或写入本地文件 tools/.cloud_verify.env（KEY=VALUE 每行一条，不入库）');
  process.exit(2);
}
const EMPTY_SHA = crypto.createHash('sha256').update('').digest('hex');
const pad = (n) => String(n).padStart(2, '0');

function s3Req({ host, path, query = '', method = 'GET', region = S3_REGION, body = null, copySource = null }) {
  const d = new Date();
  const amzDate = `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
  const dateStamp = amzDate.slice(0, 8);
  const payloadHash = body ? crypto.createHash('sha256').update(body).digest('hex') : EMPTY_SHA;
  // R5d：CopyObject 探针需把 x-amz-copy-source 一并纳入签名头集
  // （规范=头名字典序：content-sha256 < copy-source < date，脚本首跑 403 教训）。
  const ch = `host:${host}\nx-amz-content-sha256:${payloadHash}\n`
      + (copySource ? `x-amz-copy-source:${copySource}\n` : '')
      + `x-amz-date:${amzDate}\n`;
  const sh = copySource
      ? 'host;x-amz-content-sha256;x-amz-copy-source;x-amz-date'
      : 'host;x-amz-content-sha256;x-amz-date';
  const cr = `${method}\n${path}\n${query}\n${ch}\n${sh}\n${payloadHash}`;
  const scope = `${dateStamp}/${region}/s3/aws4_request`;
  const sts = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n` + crypto.createHash('sha256').update(cr).digest('hex');
  const hm = (k, s) => crypto.createHmac('sha256', k).update(s, 'utf8').digest();
  const key = hm(hm(hm(hm('AWS4' + SK, dateStamp), region), 's3'), 'aws4_request');
  const sig = crypto.createHmac('sha256', key).update(sts).digest('hex');
  return raw({
    host, path: query ? `${path}?${query}` : path, method, body,
    headers: {
      host, 'x-amz-date': amzDate, 'x-amz-content-sha256': payloadHash,
      ...(copySource ? { 'x-amz-copy-source': copySource } : {}),
      authorization: `AWS4-HMAC-SHA256 Credential=${AK}/${scope}, SignedHeaders=${sh}, Signature=${sig}`,
    },
  });
}

function wdReq({ method, path, body = null, depth = null, extraHeaders = {} }) {
  const auth = Buffer.from(WU + ':' + WP).toString('base64');
  const headers = { host: 'dav.jianguoyun.com', authorization: 'Basic ' + auth, ...extraHeaders };
  if (depth) headers['Depth'] = depth;
  if (body) headers['Content-Type'] = 'application/xml';
  return raw({ host: 'dav.jianguoyun.com', path, method, body, headers });
}

function raw({ host, path, method, headers, body = null }) {
  return new Promise((resolve) => {
    const req = https.request({ host, path, method, headers }, (r) => {
      let b = '';
      r.on('data', (c) => (b += c));
      r.on('end', () => resolve({ status: r.statusCode, body: b.slice(0, 300) }));
    });
    req.on('error', (e) => resolve({ err: e.message }));
    if (body) req.write(body);
    req.end();
  });
}

const code = (r) => (r.err ? `ERR ${r.err}` : `${r.status} ${(r.body.match(/<Code>([^<]+)<\/Code>/) || [])[1] || ''}`);

(async () => {
  console.log('=== 缤纷云 S3（App 同款签名，五探针对照）===');
  console.log('1 V2 虚拟主机式(App 当前探针) :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/', query: 'list-type=2&max-keys=1' })));
  console.log('2 V1 虚拟主机式              :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/', query: 'max-keys=1' })));
  console.log('3 V2 路径式                  :', code(await s3Req({ host: S3_HOST, path: `/${S3_BUCKET}/`, query: 'list-type=2&max-keys=1' })));
  console.log('4 HEAD 桶存在性              :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/', method: 'HEAD' })));
  console.log('5 根端点列桶(子账户预期403)  :', code(await s3Req({ host: S3_HOST, path: '/' })));
  const put = await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/lh_probe.tmp', method: 'PUT', body: 'probe' });
  console.log('6 PUT 小探针文件             :', code(put));
  if (put.status === 200) {
    console.log('7 DELETE 清理                :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/lh_probe.tmp', method: 'DELETE' })));
  }

  // R5d：附件级增量 + 归档移动/删除 真实链路复演（探针文件自动清理）。
  const probeKey = 'attachments/lh_probe_dir/p' + Date.now() + '.txt';
  const upS3 = await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/' + encodeURI(probeKey), method: 'PUT', body: 'probe-r5d' });
  console.log('8 S3 PUT 附件探针                :', code(upS3));
  if (upS3.status === 200) {
    const mv = await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`,
        path: '/' + encodeURI('media_archive/' + probeKey), method: 'PUT',
        body: '', copySource: '/' + S3_BUCKET + '/' + encodeURI(probeKey) });
    console.log('9 S3 CopyObject 归档             :', code(mv));
    console.log('10 S3 DELETE 源                  :', code(await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/' + encodeURI(probeKey), method: 'DELETE' })));
    if (mv.status === 200) {
      await s3Req({ host: `${S3_BUCKET}.${S3_HOST}`, path: '/' + encodeURI('media_archive/' + probeKey), method: 'DELETE' });
    }
  }

  console.log('\n=== 坚果云 WebDAV（App 同步链路复演）===');
  const P = `/dav/${WD_DIR}/`;
  console.log('1 PROPFIND 目录(404=未建,207=已存在):', code(await wdReq({ method: 'PROPFIND', path: P, depth: '1', body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><getcontentlength xmlns="DAV:"/><getlastmodified xmlns="DAV:"/></d:prop></d:propfind>' })));
  console.log('2 MKCOL 建目录(405=已存在亦成功)   :', code(await wdReq({ method: 'MKCOL', path: P })));
  const up = await wdReq({ method: 'PUT', path: `${P}lh_probe.tmp`, body: 'probe' });
  console.log('3 PUT 探针文件                     :', code(up));
  console.log('4 PROPFIND 应可见探针               :', code(await wdReq({ method: 'PROPFIND', path: P, depth: '1', body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>' })));
  if (up.status === 201 || up.status === 204 || up.status === 200) {
    // R5d：MOVE 归档链（App 口径：409→补建目标父→重试一次）+ 探针清理。
    const dest = `https://dav.jianguoyun.com${P}media_archive/lh_probe.tmp`;
    let mv = await wdReq({ method: 'MOVE', path: `${P}lh_probe.tmp`, extraHeaders: { Destination: dest } });
    console.log('5 MOVE 归档（App 口径）            :', code(mv));
    if (mv.status === 409 || mv.status === 404) {
      // 坚果云实测：目标父目录缺失回 404（非标准 409）——App 两态都补建重试。
      await wdReq({ method: 'MKCOL', path: `${P}media_archive/` });
      mv = await wdReq({ method: 'MOVE', path: `${P}lh_probe.tmp`, extraHeaders: { Destination: dest } });
      console.log('5b MOVE 重试（补建目标父后）         :', code(mv));
    }
    if (mv.status === 201 || mv.status === 204) {
      console.log('5c 清理归档探针                    :', code(await wdReq({ method: 'DELETE', path: `${P}media_archive/lh_probe.tmp` })));
    } else {
      console.log('5x 清理源探针                      :', code(await wdReq({ method: 'DELETE', path: `${P}lh_probe.tmp` })));
    }
  }
  console.log('\n把以上输出整段发回来即可判定。');
})();
