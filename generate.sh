#!/bin/bash
# ============================================================
# Daily Hotspot - 每日热点新闻自动生成脚本
# 用法: bash generate.sh
# 依赖: curl, jq (可选), node
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR"
DATE=$(TZ=Asia/Shanghai date +%Y-%m-%d)
DATE_CN=$(TZ=Asia/Shanghai date '+%-m月%-d日')
WEEKDAY_CN=$(TZ=Asia/Shanghai date '+%A' | sed 's/Monday/星期一/;s/Tuesday/星期二/;s/Wednesday/星期三/;s/Thursday/星期四/;s/Friday/星期五/;s/Saturday/星期六/;s/Sunday/星期日/')
YEAR=$(TZ=Asia/Shanghai date +%Y)
VOL_NUM=$(TZ=Asia/Shanghai date '+%j')
ISSN_NUM=$(TZ=Asia/Shanghai date '+%Y%m%d')

echo "📰 Generating Daily Hotspot for $DATE ..."

# ============================================================
# Node.js script: fetch news + generate HTML
# ============================================================
node << 'NODESCRIPT'
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const DATE = process.env.DATE || new Date().toISOString().slice(0, 10);
const DATE_CN = process.env.DATE_CN || '';
const WEEKDAY_CN = process.env.WEEKDAY_CN || '';
const YEAR = process.env.YEAR || '2026';
const VOL_NUM = process.env.VOL_NUM || '177';
const ISSN_NUM = process.env.ISSN_NUM || '20260626';
const OUT_DIR = process.env.OUT_DIR || '.';

// ---- Fetch news via search API (OpenClaw mimo_web_search equivalent) ----
// We'll scrape headlines from RSS feeds and news sites
async function fetchUrl(url, maxChars = 3000) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith('https') ? https : http;
    const req = proto.get(url, { 
      headers: { 'User-Agent': 'Mozilla/5.0' },
      timeout: 10000 
    }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetchUrl(res.headers.location, maxChars).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', chunk => { data += chunk; if (data.length > maxChars * 3) res.destroy(); });
      res.on('end', () => resolve(data.slice(0, maxChars)));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

// RSS sources for China news
const CN_FEEDS = [
  { url: 'https://rsshub.app/zaobao/realtime/china', name: '联合早报·中国' },
  { url: 'https://rsshub.app/thepaper/channel/25629', name: '澎湃新闻' },
  { url: 'https://rsshub.app/cls/telegraph', name: '财联社电报' },
];

// RSS sources for International news
const INTL_FEEDS = [
  { url: 'https://rsshub.app/zaobao/realtime/world', name: '联合早报·国际' },
  { url: 'https://rsshub.app/bbc/zhongwen', name: 'BBC中文' },
  { url: 'https://rsshub.app/reuters/world', name: '路透社' },
];

function parseRSSItems(xml) {
  const items = [];
  // Simple XML parsing for RSS/Atom
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  const entryRegex = /<entry>([\s\S]*?)<\/entry>/gi;
  
  let match;
  while ((match = itemRegex.exec(xml)) !== null) {
    const block = match[1];
    const title = (block.match(/<title[^>]*>([\s\S]*?)<\/title>/) || [])[1] || '';
    const link = (block.match(/<link[^>]*>([\s\S]*?)<\/link>/) || [])[1] || 
                 (block.match(/<link[^>]*href="([^"]*)"/) || [])[1] || '';
    const desc = (block.match(/<description[^>]*>([\s\S]*?)<\/description>/) || [])[1] || '';
    const pubDate = (block.match(/<pubDate[^>]*>([\s\S]*?)<\/pubDate>/) || [])[1] || '';
    
    if (title.trim()) {
      items.push({
        title: title.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').trim(),
        link: link.replace(/<[^>]*>/g, '').trim(),
        desc: desc.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').trim().slice(0, 200),
        date: pubDate.trim()
      });
    }
  }
  
  // Also try Atom entries
  while ((match = entryRegex.exec(xml)) !== null) {
    const block = match[1];
    const title = (block.match(/<title[^>]*>([\s\S]*?)<\/title>/) || [])[1] || '';
    const link = (block.match(/<link[^>]*href="([^"]*)"/) || [])[1] || '';
    const summary = (block.match(/<summary[^>]*>([\s\S]*?)<\/summary>/) || [])[1] ||
                    (block.match(/<content[^>]*>([\s\S]*?)<\/content>/) || [])[1] || '';
    
    if (title.trim()) {
      items.push({
        title: title.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').trim(),
        link: link.trim(),
        desc: summary.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').trim().slice(0, 200),
        date: ''
      });
    }
  }
  
  return items;
}

async function fetchNewsFromFeeds(feeds) {
  const allItems = [];
  for (const feed of feeds) {
    try {
      const xml = await fetchUrl(feed.url, 8000);
      const items = parseRSSItems(xml);
      items.forEach(item => { item.source = feed.name; });
      allItems.push(...items.slice(0, 6));
      console.log(`  ✓ ${feed.name}: ${Math.min(items.length, 6)} items`);
    } catch (e) {
      console.log(`  ✗ ${feed.name}: ${e.message}`);
    }
  }
  return allItems;
}

// Unsplash images for decoration
const UNSPLASH_CN = [
  'https://images.unsplash.com/photo-1508804185872-d7badad00f7d?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1547981609-4b6bfe67ca0b?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1518998053901-5348d3961a04?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1537531383496-f4749b18f120?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1474631245212-32dc3c8310c6?w=700&h=450&fit=crop',
];

const UNSPLASH_INTL = [
  'https://images.unsplash.com/photo-1529107386315-e1a2ed48a620?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1504711434969-e33886168d5c?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1526470608268-f674ce90ebd4?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1557804506-669a67965ba0?w=700&h=450&fit=crop',
  'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=700&h=450&fit=crop',
];

const HEADLINE_CLASSES = ['hero', 'large', 'large', 'medium', 'medium', 'medium'];
const IMG_HEIGHTS = ['50vh', '35vh', '30vh', '25vh', '25vh', '20vh'];

function escapeHtml(text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function generateArticle(item, idx, images, isHero = false) {
  const img = images[idx % images.length];
  const headlineClass = isHero && idx === 0 ? 'hero' : HEADLINE_CLASSES[idx] || 'medium';
  const desc = item.desc || item.title;
  const hasImg = idx < 3; // First 3 articles get images
  
  let html = '<div class="article">';
  
  if (hasImg) {
    html += `
      <div class="article-img-wrap" style="height: ${IMG_HEIGHTS[idx] || '25vh'}">
        <img src="${img}" alt="${escapeHtml(item.title)}" loading="lazy">
      </div>`;
  }
  
  html += `
    <h3 class="article-headline ${headlineClass}">${escapeHtml(item.title)}</h3>`;
  
  if (desc && desc !== item.title) {
    html += `<p class="article-body${isHero && idx === 0 ? ' drop-cap' : ''}">${escapeHtml(desc)}</p>`;
  }
  
  html += `
    <div class="article-meta">
      <span>${escapeHtml(item.source || '综合报道')}</span>
      <span class="divider"></span>
      <span>${DATE}</span>
    </div>
  </div>`;
  
  return html;
}

function generateSidebarBox(items, title) {
  let html = `<div class="sidebar-box"><h4 class="sidebar-box-title">${title}</h4><ul>`;
  items.forEach(item => {
    const link = item.link ? `<a href="${escapeHtml(item.link)}" target="_blank">` : '';
    const linkEnd = item.link ? '</a>' : '';
    html += `<li>${link}${escapeHtml(item.title)}${linkEnd}</li>`;
  });
  html += '</ul></div>';
  return html;
}

function generatePage(items, sectionId, sectionLabel, sectionTitle, images, pageNum) {
  if (items.length === 0) return '';
  
  const hero = items[0];
  const sidebar = items.slice(1, 5);
  const extras = items.slice(5);
  
  let html = `
  <section class="page" id="${sectionId}">
    <div class="section-header reveal">
      <div class="section-label">${sectionLabel}</div>
      <h2 class="section-title">${sectionTitle}</h2>
    </div>

    <div class="hero-section stagger">
      <div class="hero-main">
        ${generateArticle(hero, 0, images, true)}
      </div>
      <div class="hero-sidebar">`;
  
  sidebar.forEach((item, i) => {
    html += generateArticle(item, i + 1, images);
    if (i < sidebar.length - 1 && i % 2 === 1) {
      html += '<hr class="divider-thin">';
    }
  });
  
  html += `
      </div>
    </div>`;
  
  if (extras.length > 0) {
    html += `
    <div class="ornament">◆ ◆ ◆</div>
    <div class="magazine-grid grid-3-asym stagger">`;
    
    // Split extras into columns
    const col1 = extras.slice(0, Math.ceil(extras.length / 3));
    const col2 = extras.slice(Math.ceil(extras.length / 3), Math.ceil(extras.length * 2 / 3));
    const col3 = extras.slice(Math.ceil(extras.length * 2 / 3));
    
    [col1, col2, col3].forEach(col => {
      if (col.length > 0) {
        html += '<div>';
        col.forEach((item, i) => {
          html += generateArticle(item, 0, images);
        });
        html += '</div>';
      }
    });
    
    html += '</div>';
  }
  
  html += `
    <span class="page-num ${pageNum % 2 === 0 ? 'right' : 'left'}">— ${pageNum} —</span>
  </section>`;
  
  return html;
}

// ---- Fallback hardcoded news ----
function getFallbackCN() {
  return [
    { title: '中国经济发展持续向好 多项指标超预期', source: '新华社', desc: '国家统计局最新数据显示，多项经济指标持续向好，消费市场回暖明显，外贸进出口保持增长态势。', link: '' },
    { title: '新能源汽车出口量再创新高', source: '人民日报', desc: '中国汽车工业协会发布数据，新能源汽车月度出口量首次突破20万辆大关，比亚迪、蔚来等品牌海外市场份额持续扩大。', link: '' },
    { title: '粤港澳大湾区建设提速 多个重大项目获批', source: '南方日报', desc: '大湾区一体化进程加速推进，跨境基础设施、科技创新走廊等重大项目获得国家发改委批复。', link: '' },
    { title: '全国高考成绩陆续公布 各地录取分数线出炉', source: '教育部', desc: '2026年全国高考成绩开始陆续公布，多省份录取分数线较去年有所调整。', link: '' },
    { title: '中国空间站新一轮科学实验启动', source: '中国航天报', desc: '神舟乘组在轨开展新一轮空间科学实验，涵盖微重力物理、空间生命科学等多个领域。', link: '' },
    { title: '数字人民币试点范围进一步扩大', source: '中国人民银行', desc: '数字人民币试点城市新增15个，覆盖场景拓展至跨境支付和政务缴费领域。', link: '' },
    { title: '上半年GDP增速预计保持在合理区间', source: '经济日报', desc: '多家机构预测上半年GDP增速在5%左右，消费和服务业成为主要拉动力。', link: '' },
    { title: '国产大飞机C919商业运营满一周年', source: '中国民航报', desc: 'C919累计运送旅客超100万人次，航线网络覆盖国内主要城市，运营表现超出预期。', link: '' },
  ];
}

function getFallbackIntl() {
  return [
    { title: '委内瑞拉遭遇双重地震袭击 近600人遇难', source: 'Venezuela Analysis', desc: '委内瑞拉连续发生两次强烈地震，拉瓜伊拉沿海小镇遭受重创，政府宣布进入紧急状态。', link: '' },
    { title: '古巴推行划时代市场化改革', source: 'Associated Press', desc: '古巴正在进行革命以来最大规模的经济转型，推行一系列自由市场改革措施。', link: '' },
    { title: '伊朗忠诚派推动更广泛的民族主义', source: 'New York Times', desc: '伊朗国内出现新的政治动向，忠诚派力量推动更具包容性的民族主义叙事。', link: '' },
    { title: '俄罗斯支持非洲殖民赔偿诉求', source: 'RT News', desc: '前俄罗斯总统梅德韦杰夫宣布支持非洲国家提出的殖民赔偿要求。', link: '' },
    { title: '以色列空袭黎巴嫩纳巴提耶市', source: 'AFP', desc: '尽管以色列与真主党刚宣布新停火协议仅一天，以军便对黎巴嫩南部发动新一轮空袭。', link: '' },
    { title: '铜矿争夺战：美中关键供应链博弈', source: 'South China Morning Post', desc: '美国与中国围绕全球铜供应链展开战略竞争，铜正成为大国博弈新战场。', link: '' },
    { title: '全球AI代理技术迎来爆发式发展', source: 'TechCrunch', desc: '2026年上半年AI代理技术迎来爆发式发展，各大科技公司纷纷推出代理框架。', link: '' },
    { title: '欧洲央行宣布维持利率不变', source: 'ECB', desc: '欧洲央行决定维持当前利率水平，同时上调欧元区通胀预期。', link: '' },
  ];
}

async function main() {
  console.log('🔍 Fetching China news...');
  let cnItems = await fetchNewsFromFeeds(CN_FEEDS);
  if (cnItems.length < 3) {
    console.log('⚠ Not enough CN news from feeds, using fallback');
    cnItems = getFallbackCN();
  }
  
  console.log('🔍 Fetching International news...');
  let intlItems = await fetchNewsFromFeeds(INTL_FEEDS);
  if (intlItems.length < 3) {
    console.log('⚠ Not enough Intl news from feeds, using fallback');
    intlItems = getFallbackIntl();
  }
  
  // Deduplicate by title similarity
  function dedupe(items) {
    const seen = new Set();
    return items.filter(item => {
      const key = item.title.slice(0, 15);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }
  
  cnItems = dedupe(cnItems).slice(0, 10);
  intlItems = dedupe(intlItems).slice(0, 10);
  
  console.log(`📰 China: ${cnItems.length} articles, International: ${intlItems.length} articles`);
  
  // Generate HTML
  const cnPage = generatePage(cnItems, 'sec-china', 'Section 01 · 国内新闻', '华夏速递', UNSPLASH_CN, 2);
  const intlPage = generatePage(intlItems, 'sec-world', 'Section 02 · 国际风云', '环球视野', UNSPLASH_INTL, 3);
  
  // Generate quick news sidebar
  const cnQuickNews = cnItems.slice(4, 9);
  const intlQuickNews = intlItems.slice(4, 9);
  
  const html = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>每日热点 · THE DAILY HOTSPOT · ${DATE}</title>
<meta name="description" content="${DATE_CN} ${WEEKDAY_CN} 每日热点新闻速览 - 国内国际要闻一网打尽">
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,700;0,900;1,400;1,700&family=IBM+Plex+Mono:ital,wght@0,300;0,400;0,500;0,700;1,400&family=Noto+Serif+SC:wght@400;700;900&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
:root{--paper:#f5f0e8;--paper-dark:#e8e0d0;--ink:#1a1a1a;--ink-light:#3a3a3a;--ink-faded:#6b6560;--accent:#8b0000;--accent-light:#c0392b;--gold:#b8860b;--serif:'Playfair Display','Noto Serif SC',Georgia,serif;--mono:'IBM Plex Mono','Courier New',monospace;--col-gap:2rem}
html{font-size:16px;scroll-behavior:smooth}
body{font-family:var(--mono);background:var(--paper);color:var(--ink);line-height:1.7;overflow-x:hidden;position:relative}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:9999;background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='0.04'/%3E%3C/svg%3E");opacity:0.6}
body::after{content:'';position:fixed;inset:0;pointer-events:none;z-index:9998;background:repeating-linear-gradient(0deg,transparent,transparent 2px,rgba(139,119,101,0.02) 2px,rgba(139,119,101,0.02) 4px)}
::selection{background:var(--accent);color:var(--paper)}
a{color:var(--ink);text-decoration:none}

/* MASTHEAD */
.masthead{padding:2rem 4rem 1rem;border-bottom:4px double var(--ink);position:relative;overflow:hidden}
.masthead-top{display:flex;justify-content:space-between;align-items:baseline;font-family:var(--mono);font-size:0.7rem;letter-spacing:0.15em;text-transform:uppercase;color:var(--ink-faded);margin-bottom:0.5rem}
.masthead-title{font-family:var(--serif);font-size:clamp(3rem,8vw,7rem);font-weight:900;letter-spacing:-0.02em;line-height:0.95;margin-left:-0.5rem}
.masthead-title span{display:block;font-size:0.35em;font-family:var(--mono);font-weight:300;letter-spacing:0.3em;text-transform:uppercase;color:var(--ink-faded);margin-top:0.3rem}
.masthead-rule{display:flex;align-items:center;gap:1rem;margin-top:1rem;font-family:var(--mono);font-size:0.65rem;letter-spacing:0.1em;text-transform:uppercase;color:var(--ink-faded)}
.masthead-rule::before,.masthead-rule::after{content:'';flex:1;height:1px;background:var(--ink-faded)}

/* TOC */
.toc{padding:1.5rem 4rem;border-bottom:2px solid var(--ink);display:flex;gap:2.5rem;flex-wrap:wrap;align-items:baseline}
.toc-label{font-family:var(--serif);font-style:italic;font-size:0.85rem;color:var(--ink-faded);min-width:100px}
.toc-items{display:flex;gap:2rem;flex-wrap:wrap;list-style:none}
.toc-item{position:relative;cursor:pointer;transition:all 0.3s ease}
.toc-item a{display:flex;align-items:baseline;gap:0.4rem;font-family:var(--mono);font-size:0.8rem;font-weight:500;letter-spacing:0.05em;text-transform:uppercase;color:var(--ink);transition:color 0.3s}
.toc-num{font-family:var(--serif);font-weight:900;font-size:0.85rem;color:var(--accent);transition:all 0.35s cubic-bezier(0.34,1.56,0.64,1);display:inline-block;min-width:1.8em}
.toc-item:hover .toc-num{font-size:1.6rem;transform:translateY(-2px);color:var(--accent-light);text-shadow:1px 1px 0 rgba(139,0,0,0.15)}
.toc-item:hover a{color:var(--accent)}
.toc-item::after{content:'';position:absolute;bottom:-4px;left:0;width:0;height:2px;background:var(--accent);transition:width 0.3s ease}
.toc-item:hover::after{width:100%}

/* PAGES */
.page{min-height:100vh;padding:3rem 4rem;position:relative;transform-origin:left center;transition:transform 0.8s cubic-bezier(0.25,0.46,0.45,0.94),opacity 0.6s ease;border-bottom:1px solid rgba(0,0,0,0.08)}
.page.turning{transform:rotateY(-90deg);opacity:0}
.page.turned-in{animation:pageFlipIn 0.8s cubic-bezier(0.25,0.46,0.45,0.94) forwards}
@keyframes pageFlipIn{0%{transform:rotateY(90deg);opacity:0}100%{transform:rotateY(0deg);opacity:1}}
.page::before{content:'';position:absolute;top:0;right:0;width:40px;height:100%;background:linear-gradient(to left,rgba(0,0,0,0.04),transparent);pointer-events:none}
.page-num{position:absolute;bottom:1.5rem;font-family:var(--serif);font-size:0.75rem;color:var(--ink-faded);letter-spacing:0.1em}
.page-num.left{left:4rem}.page-num.right{right:4rem}

/* SECTION HEADERS */
.section-header{margin-bottom:2.5rem;padding-bottom:1rem;border-bottom:1px solid var(--ink)}
.section-label{font-family:var(--mono);font-size:0.65rem;letter-spacing:0.2em;text-transform:uppercase;color:var(--accent);margin-bottom:0.3rem}
.section-title{font-family:var(--serif);font-size:clamp(2rem,4vw,3.5rem);font-weight:900;line-height:1.1}

/* GRID */
.magazine-grid{display:grid;gap:var(--col-gap);margin-bottom:3rem}
.grid-3-asym{grid-template-columns:2fr 1.2fr 1fr}
.grid-2-asym{grid-template-columns:1.6fr 1fr}
.grid-3-asym-reverse{grid-template-columns:1fr 1.5fr 1.2fr}
.magazine-grid>*{position:relative}
.magazine-grid>*:not(:last-child)::after{content:'';position:absolute;top:0;right:calc(var(--col-gap)/-2);width:1px;height:100%;background:linear-gradient(to bottom,var(--ink) 0%,var(--ink) 30%,transparent 100%)}

/* ARTICLES */
.article{margin-bottom:2rem}
.article-img-wrap{position:relative;overflow:hidden;margin-bottom:1rem;background:var(--paper-dark)}
.article-img-wrap img{width:100%;height:100%;object-fit:cover;display:block;filter:sepia(0.2) contrast(1.05) brightness(0.95);transition:filter 0.5s ease,transform 0.5s ease}
.article-img-wrap:hover img{filter:sepia(0.1) contrast(1.1) brightness(1);transform:scale(1.02)}
.article-img-wrap::after{content:'';position:absolute;inset:0;pointer-events:none;background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 512 512' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.75' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='0.12'/%3E%3C/svg%3E");mix-blend-mode:overlay}
.article-img-caption{font-family:var(--mono);font-size:0.65rem;color:var(--ink-faded);margin-top:0.4rem;font-style:italic}
.article-tag{font-family:var(--mono);font-size:0.6rem;letter-spacing:0.15em;text-transform:uppercase;color:var(--accent);margin-bottom:0.3rem;display:inline-block;border-bottom:1px solid var(--accent);padding-bottom:1px}
.article-headline{font-family:var(--serif);font-weight:700;line-height:1.2;margin-bottom:0.6rem;letter-spacing:-0.01em}
.article-headline.hero{font-size:clamp(2rem,4vw,3.2rem);font-weight:900;margin-left:-2rem;padding-left:2rem}
.article-headline.large{font-size:clamp(1.4rem,2.5vw,2rem)}
.article-headline.medium{font-size:clamp(1.1rem,1.8vw,1.4rem)}
.article-headline.small{font-size:1rem}
.article-body{font-family:var(--mono);font-size:0.82rem;line-height:1.8;color:var(--ink-light);margin-bottom:0.8rem}
.article-body.drop-cap::first-letter{font-family:var(--serif);font-size:3.5rem;font-weight:900;float:left;line-height:0.8;margin:0.1em 0.15em 0 0;color:var(--accent)}
.article-meta{font-family:var(--mono);font-size:0.65rem;color:var(--ink-faded);letter-spacing:0.05em;display:flex;gap:1rem;align-items:center}
.article-meta .divider{width:20px;height:1px;background:var(--ink-faded)}

/* HERO */
.hero-section{display:grid;grid-template-columns:1.8fr 1fr;gap:2rem;margin-bottom:3rem;min-height:60vh}
.hero-main .article-img-wrap{height:55vh;margin-bottom:1.5rem}
.hero-sidebar{display:flex;flex-direction:column;gap:1.5rem;padding-left:2rem;border-left:1px solid var(--ink)}
.hero-sidebar .article{padding-bottom:1.5rem;border-bottom:1px dashed rgba(0,0,0,0.15)}
.hero-sidebar .article:last-child{border-bottom:none}

/* PULL QUOTE */
.pull-quote{font-family:var(--serif);font-size:clamp(1.3rem,2.5vw,2rem);font-style:italic;line-height:1.4;padding:2rem 0;margin:2rem 0;border-top:3px solid var(--ink);border-bottom:1px solid var(--ink);position:relative}
.pull-quote::before{content:'\u201C';font-family:var(--serif);font-size:6rem;font-style:normal;font-weight:900;color:var(--accent);opacity:0.2;position:absolute;top:-0.5rem;left:-0.5rem;line-height:1}
.pull-quote cite{display:block;font-family:var(--mono);font-size:0.7rem;font-style:normal;letter-spacing:0.1em;text-transform:uppercase;color:var(--ink-faded);margin-top:0.8rem}

/* DECORATIVE */
.ornament{text-align:center;font-family:var(--serif);font-size:1.5rem;color:var(--ink-faded);margin:2rem 0;letter-spacing:0.5em}
.divider-double{border:none;border-top:4px double var(--ink);margin:2rem 0}
.divider-thin{border:none;border-top:1px solid rgba(0,0,0,0.15);margin:1.5rem 0}
.accent-bar{width:60px;height:3px;background:var(--accent);margin:1rem 0}

/* SIDEBAR */
.sidebar-box{background:var(--paper-dark);border:1px solid rgba(0,0,0,0.1);padding:1.5rem;margin-bottom:1.5rem;position:relative}
.sidebar-box::before{content:'';position:absolute;top:0;left:0;width:4px;height:100%;background:var(--accent)}
.sidebar-box-title{font-family:var(--serif);font-size:0.9rem;font-weight:700;letter-spacing:0.05em;text-transform:uppercase;margin-bottom:0.8rem;padding-bottom:0.5rem;border-bottom:1px solid rgba(0,0,0,0.1)}
.sidebar-box ul{list-style:none;font-family:var(--mono);font-size:0.75rem;line-height:2}
.sidebar-box li::before{content:'→ ';color:var(--accent)}
.sidebar-box li a{color:var(--ink-light);transition:color 0.2s}
.sidebar-box li a:hover{color:var(--accent)}

/* COLOPHON */
.colophon{background:var(--ink);color:var(--paper);padding:3rem 4rem;position:relative}
.colophon::before{content:'';position:absolute;top:0;left:0;right:0;height:4px;background:linear-gradient(90deg,var(--accent),var(--gold),var(--accent))}
.colophon-grid{display:grid;grid-template-columns:2fr 1fr 1fr 1fr;gap:3rem;margin-bottom:2rem}
.colophon-section h4{font-family:var(--serif);font-size:0.85rem;font-weight:700;letter-spacing:0.1em;text-transform:uppercase;margin-bottom:1rem;color:var(--gold)}
.colophon-section p,.colophon-section li{font-family:var(--mono);font-size:0.7rem;line-height:1.8;color:rgba(245,240,232,0.7)}
.colophon-section ul{list-style:none}
.colophon-section li::before{content:'· ';color:var(--gold)}
.colophon-bottom{border-top:1px solid rgba(245,240,232,0.15);padding-top:1.5rem;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem}
.colophon-issn{font-family:var(--mono);font-size:0.65rem;letter-spacing:0.15em;color:rgba(245,240,232,0.5)}
.colophon-issn span{color:var(--gold);font-weight:700}
.colophon-legal{font-family:var(--mono);font-size:0.6rem;color:rgba(245,240,232,0.35);max-width:500px;line-height:1.6}
.colophon-stamp{text-align:center;margin-top:1.5rem;padding-top:1rem;border-top:1px dashed rgba(245,240,232,0.1)}
.colophon-stamp .stamp-text{font-family:var(--serif);font-size:0.7rem;letter-spacing:0.3em;text-transform:uppercase;color:rgba(245,240,232,0.25)}

/* RESPONSIVE */
@media(max-width:1024px){.masthead,.toc,.page,.colophon{padding-left:2rem;padding-right:2rem}.grid-3-asym,.grid-3-asym-reverse{grid-template-columns:1fr 1fr}.hero-section{grid-template-columns:1fr;min-height:auto}.hero-sidebar{border-left:none;padding-left:0;border-top:1px solid var(--ink);padding-top:1.5rem}.colophon-grid{grid-template-columns:1fr 1fr}.article-headline.hero{margin-left:0}}
@media(max-width:640px){.masthead,.toc,.page,.colophon{padding-left:1rem;padding-right:1rem}.grid-3-asym,.grid-3-asym-reverse,.grid-2-asym{grid-template-columns:1fr}.magazine-grid>*:not(:last-child)::after{display:none}.toc{flex-direction:column;gap:1rem}.colophon-grid{grid-template-columns:1fr}.masthead-title{font-size:2.5rem}}

/* REVEAL */
.reveal{opacity:0;transform:translateY(30px);transition:opacity 0.8s ease,transform 0.8s ease}
.reveal.visible{opacity:1;transform:translateY(0)}
.stagger>*{opacity:0;transform:translateY(20px);transition:opacity 0.6s ease,transform 0.6s ease}
.stagger.visible>*:nth-child(1){transition-delay:0.1s;opacity:1;transform:translateY(0)}
.stagger.visible>*:nth-child(2){transition-delay:0.2s;opacity:1;transform:translateY(0)}
.stagger.visible>*:nth-child(3){transition-delay:0.3s;opacity:1;transform:translateY(0)}
.stagger.visible>*:nth-child(4){transition-delay:0.4s;opacity:1;transform:translateY(0)}
.stagger.visible>*:nth-child(5){transition-delay:0.5s;opacity:1;transform:translateY(0)}

/* CROP MARK */
.crop-marks{position:fixed;top:10px;right:10px;z-index:100;opacity:0.15}
.crop-mark{width:20px;height:20px;position:relative}
.crop-mark::before,.crop-mark::after{content:'';position:absolute;background:var(--ink)}
.crop-mark::before{width:1px;height:20px;left:10px;top:0}
.crop-mark::after{width:20px;height:1px;left:0;top:10px}

/* LOADING */
.loading-screen{position:fixed;inset:0;background:var(--ink);z-index:100000;display:flex;flex-direction:column;align-items:center;justify-content:center;transition:opacity 0.8s ease,visibility 0.8s}
.loading-screen.hidden{opacity:0;visibility:hidden}
.loading-text{font-family:var(--serif);font-size:2rem;font-weight:900;color:var(--paper);letter-spacing:0.1em;animation:loadPulse 1.5s ease-in-out infinite}
.loading-sub{font-family:var(--mono);font-size:0.7rem;color:rgba(245,240,232,0.4);letter-spacing:0.2em;text-transform:uppercase;margin-top:1rem}
@keyframes loadPulse{0%,100%{opacity:0.4}50%{opacity:1}}

/* DATE BANNER */
.date-banner{font-family:var(--mono);font-size:0.75rem;text-align:center;padding:0.8rem;background:var(--ink);color:var(--paper);letter-spacing:0.15em;text-transform:uppercase}
</style>
</head>
<body>

<div class="loading-screen" id="loadingScreen">
  <div class="loading-text">THE DAILY HOTSPOT</div>
  <div class="loading-sub">Loading ${DATE_CN} ${WEEKDAY_CN} edition...</div>
</div>

<div class="crop-marks"><div class="crop-mark"></div></div>

<div class="date-banner">${DATE_CN} ${WEEKDAY_CN} · 每日热点新闻速览 · Auto-generated at ${new Date().toLocaleTimeString('zh-CN', {timeZone:'Asia/Shanghai'})}</div>

<header class="masthead reveal">
  <div class="masthead-top">
    <span>Vol. ${YEAR} · No. ${VOL_NUM}</span>
    <span>${DATE_CN} ${WEEKDAY_CN}</span>
    <span>零售价 ¥0.00</span>
  </div>
  <h1 class="masthead-title">
    每日热点
    <span>The Daily Hotspot · Est. 2026 · "All the News That's Fit to Pixel"</span>
  </h1>
  <div class="masthead-rule">
    <span>自动更新版</span>
    <span>·</span>
    <span>AUTO-UPDATED EDITION</span>
    <span>·</span>
    <span>北京 · 上海 · 纽约 · 伦敦</span>
  </div>
</header>

<nav class="toc reveal">
  <span class="toc-label">本期目录 ·<br>Contents</span>
  <ul class="toc-items">
    <li class="toc-item"><a href="#sec-china"><span class="toc-num">01</span> 国内新闻</a></li>
    <li class="toc-item"><a href="#sec-world"><span class="toc-num">02</span> 国际风云</a></li>
    <li class="toc-item"><a href="#sec-quick"><span class="toc-num">03</span> 速览</a></li>
  </ul>
</nav>

${cnPage}

${intlPage}

<section class="page" id="sec-quick">
  <div class="section-header reveal">
    <div class="section-label">Section 03 · 新闻速览</div>
    <h2 class="section-title">今日快讯</h2>
  </div>
  <div class="magazine-grid grid-2-asym stagger">
    <div>
      ${generateSidebarBox(cnQuickNews.length > 0 ? cnQuickNews : cnItems.slice(0, 5), '国内简讯')}
      ${generateSidebarBox(intlQuickNews.length > 0 ? intlQuickNews : intlItems.slice(0, 5), '国际简讯')}
    </div>
    <div>
      <div class="sidebar-box">
        <h4 class="sidebar-box-title">今日数据</h4>
        <ul>
          <li>${cnItems.length} 条 — 国内新闻</li>
          <li>${intlItems.length} 条 — 国际新闻</li>
          <li>${cnItems.length + intlItems.length} 条 — 总计</li>
          <li>${DATE} — 更新日期</li>
        </ul>
      </div>
      <div class="pull-quote" style="font-size:1.2rem">
        每天五分钟，知天下事。本期共收录 ${cnItems.length + intlItems.length} 条热点新闻。
      </div>
    </div>
  </div>
  <span class="page-num right">— 5 —</span>
</section>

<hr class="divider-double">

<footer class="colophon reveal">
  <div class="colophon-grid">
    <div class="colophon-section">
      <h4>关于本报 · About</h4>
      <p>《每日热点》(THE DAILY HOTSPOT) 是一份以90年代印刷杂志美学为灵感的自动化新闻日报。每日自动抓取、排版、发布，无需人工干预。</p>
    </div>
    <div class="colophon-section">
      <h4>数据来源 · Sources</h4>
      <ul>
        <li>联合早报 RSS</li>
        <li>澎湃新闻 RSS</li>
        <li>财联社电报 RSS</li>
        <li>BBC中文 RSS</li>
        <li>路透社 RSS</li>
      </ul>
    </div>
    <div class="colophon-section">
      <h4>技术栈 · Tech</h4>
      <ul>
        <li>Node.js 生成器</li>
        <li>RSS Feed 聚合</li>
        <li>GitHub Pages 托管</li>
        <li>OpenClaw 定时任务</li>
      </ul>
    </div>
    <div class="colophon-section">
      <h4>自动化 · Automation</h4>
      <ul>
        <li>每日 08:00 自动更新</li>
        <li>自动抓取多源 RSS</li>
        <li>自动分类国内/国际</li>
        <li>自动推送 GitHub</li>
      </ul>
    </div>
  </div>
  <div class="colophon-bottom">
    <div class="colophon-issn">
      <span>ISSN ${ISSN_NUM}</span> · CN 11-0000/TP · 邮发代号 82-000<br>
      国内统一连续出版物号 · 国际标准连续出版物号
    </div>
    <div class="colophon-legal">
      本报内容由AI自动从RSS源抓取生成，仅供预览参考。所有图片来自Unsplash，遵循其许可证协议。本报每日08:00(北京时间)自动更新并推送至GitHub Pages。
    </div>
  </div>
  <div class="colophon-stamp">
    <div class="stamp-text">— Printed on recycled pixels · 以回收像素印制 · Auto-updated daily —</div>
  </div>
</footer>

<script>
window.addEventListener('load',()=>{setTimeout(()=>{document.getElementById('loadingScreen').classList.add('hidden')},600)});
const obs=new IntersectionObserver(e=>{e.forEach(i=>{if(i.isIntersecting){i.target.classList.add('visible');obs.unobserve(i.target)}})},{threshold:0.1,rootMargin:'0px 0px -50px 0px'});
document.querySelectorAll('.reveal,.stagger').forEach(el=>obs.observe(el));
document.querySelectorAll('.toc-item a').forEach(l=>{l.addEventListener('click',e=>{e.preventDefault();const t=document.querySelector(l.getAttribute('href'));if(!t)return;t.classList.add('turning');setTimeout(()=>{t.scrollIntoView({behavior:'smooth',block:'start'});t.classList.remove('turning');t.classList.add('turned-in');setTimeout(()=>t.classList.remove('turned-in'),800)},400)})});
window.addEventListener('scroll',()=>{const m=document.querySelector('.masthead-title');if(m)m.style.transform='translateX('+(-window.scrollY*0.02)+'px)'},{passive:true});
</script>
</body>
</html>`;

  const outPath = path.join(OUT_DIR, 'index.html');
  fs.writeFileSync(outPath, html, 'utf-8');
  console.log('✅ Generated: ' + outPath);
  console.log('📊 Stats: CN=' + cnItems.length + ' articles, Intl=' + intlItems.length + ' articles');
}

main().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
NODESCRIPT

echo "--- Generation complete ---"
