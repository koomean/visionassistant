/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';

  /* ==========================================================================
     1. Starfield Background (shared visual language with index & architecture)
     ========================================================================== */
  const skyCanvas = document.querySelector('#starfield');
  const skyCtx = skyCanvas?.getContext('2d');
  if (skyCanvas && skyCtx) {
    let stars = [];
    const seeded = seed => () => {
      seed = (seed * 16807) % 2147483647;
      return (seed - 1) / 2147483646;
    };
    const drawSky = () => {
      const w = window.innerWidth;
      const h = window.innerHeight;
      const dpr = Math.min(window.devicePixelRatio || 1, 1.8);
      skyCanvas.width = Math.round(w * dpr);
      skyCanvas.height = Math.round(h * dpr);
      skyCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const rand = seeded(17072026);
      const count = Math.min(140, Math.round((w * h) / 8500));
      stars = Array.from({ length: count }, () => ({
        x: rand() * w,
        y: rand() * h,
        r: 0.45 + rand() * 0.85,
        a: 0.18 + rand() * 0.55
      }));
      skyCtx.clearRect(0, 0, w, h);
      for (const s of stars) {
        skyCtx.beginPath();
        skyCtx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
        skyCtx.fillStyle = `rgba(197,211,239,${s.a})`;
        skyCtx.fill();
      }
    };
    window.addEventListener('resize', drawSky, { passive: true });
    drawSky();
  }

  /* ==========================================================================
     2. Built-in Interactive Scenes (Deterministic Fixtures + Depth + OCR)
     ========================================================================== */
  const SCENES = {
    cafe: {
      id: 'cafe',
      defaultPromptTh: 'ในภาพมีอะไรบ้าง?',
      defaultPromptEn: 'What is in this photo?',
      summaryTh: 'ในภาพมีป้ายเวลาเปิดทำการ (OPEN 9 AM - 8 PM) ด้านขวาบน ป้ายเมนูอาหารด้านซ้าย (ข้าวผัด 60, ต้มยำ 80, ชา 30) ขวดน้ำดื่มสีเขียวขนาด 500 ml ตรงกลาง และขวดน้ำส้มขนาด 250 ml ด้านขวา',
      summaryEn: 'The photo shows an OPEN 9 AM - 8 PM sign at the top right, a food menu on the left (Fried rice 60, Tom yum 80, Tea 30), a green 500 ml spring water bottle in the center, and an orange 250 ml juice bottle on the right.',
      sources: [
        {
          id: 0,
          kind: 'menu',
          kindTh: 'เมนูอาหาร',
          kindEn: 'Menu',
          posTh: 'ตรงกลาง · ซ้าย',
          posEn: 'Center · Left',
          rect: { x: 0.04, y: 0.14, w: 0.29, h: 0.74 },
          text: 'MENU\nFried rice 60\nTom yum 80\nTea 30',
          summaryTh: 'เมนูอาหารมี 3 รายการ ได้แก่ ข้าวผัด (Fried rice) 60 บาท, ต้มยำ (Tom yum) 80 บาท และชา (Tea) 30 บาท',
          summaryEn: 'Food menu with 3 items: Fried rice (60), Tom yum (80), and Tea (30).',
          depth: 1.10
        },
        {
          id: 1,
          kind: 'sign',
          kindTh: 'ป้าย',
          kindEn: 'Sign',
          posTh: 'ส่วนบน · ขวา',
          posEn: 'Top · Right',
          rect: { x: 0.39, y: 0.07, w: 0.49, h: 0.17 },
          text: 'OPEN\n9 AM - 8 PM',
          summaryTh: 'ป้ายแจ้งเวลาเปิดทำการ ตั้งแต่ 9 โมงเช้า ถึง 2 ทุ่ม (9 AM - 8 PM)',
          summaryEn: 'Sign indicating opening hours from 9 AM to 8 PM.',
          depth: 1.45
        },
        {
          id: 2,
          kind: 'bottle_label',
          kindTh: 'ฉลากขวด',
          kindEn: 'Bottle label',
          posTh: 'ตรงกลาง',
          posEn: 'Center',
          rect: { x: 0.41, y: 0.54, w: 0.18, h: 0.21 },
          text: 'SPRING\nWATER\n500 ml',
          summaryTh: 'ฉลากขวดน้ำดื่ม (Spring Water) ปริมาตรสุทธิ 500 มิลลิลิตร',
          summaryEn: 'Spring Water bottle label, net volume 500 ml.',
          depth: 0.72
        },
        {
          id: 3,
          kind: 'bottle_label',
          kindTh: 'ฉลากขวด',
          kindEn: 'Bottle label',
          posTh: 'ตรงกลาง · ขวา',
          posEn: 'Center · Right',
          rect: { x: 0.70, y: 0.54, w: 0.18, h: 0.21 },
          text: 'ORANGE\nJUICE\n250 ml',
          summaryTh: 'ฉลากขวดน้ำส้ม (Orange Juice) ปริมาตรสุทธิ 250 มิลลิลิตร',
          summaryEn: 'Orange Juice bottle label, net volume 250 ml.',
          depth: 0.85
        }
      ],
      objects: [
        {
          keywords: ['ขวดน้ำดื่ม', 'ขวดน้ำ', 'ขวดสีเขียว', 'น้ำดื่ม', 'water', 'spring', 'green bottle'],
          nameTh: 'ขวดน้ำดื่มสีเขียว',
          nameEn: 'The green spring water bottle',
          rect: { x: 0.40, y: 0.32, w: 0.20, h: 0.56 },
          point: { x: 0.50, y: 0.58 },
          depth: 0.72,
          centered: true,
          dirTh: 'กลาง',
          dirEn: 'center'
        },
        {
          keywords: ['ขวดน้ำส้ม', 'น้ำส้ม', 'ขวดสีส้ม', 'orange juice', 'orange', 'juice'],
          nameTh: 'ขวดน้ำส้ม',
          nameEn: 'The orange juice bottle',
          rect: { x: 0.69, y: 0.32, w: 0.20, h: 0.56 },
          point: { x: 0.79, y: 0.58 },
          depth: 0.85,
          centered: false,
          dirTh: 'ขวา',
          dirEn: 'right'
        },
        {
          keywords: ['เมนู', 'รายการอาหาร', 'menu'],
          nameTh: 'ป้ายเมนูอาหาร',
          nameEn: 'The food menu',
          rect: { x: 0.04, y: 0.14, w: 0.29, h: 0.74 },
          point: { x: 0.18, y: 0.48 },
          depth: 1.10,
          centered: false,
          dirTh: 'ซ้าย',
          dirEn: 'left'
        },
        {
          keywords: ['ป้ายเปิด', 'ป้ายร้าน', 'open', 'sign'],
          nameTh: 'ป้ายเวลาเปิดร้าน',
          nameEn: 'The OPEN sign',
          rect: { x: 0.39, y: 0.07, w: 0.49, h: 0.17 },
          point: { x: 0.63, y: 0.15 },
          depth: 1.45,
          centered: false,
          dirTh: 'ขวาบน',
          dirEn: 'upper right'
        }
      ],
      draw(ctx, w, h) {
        ctx.fillStyle = '#dbdde0';
        ctx.fillRect(0, 0, w, h);
        // Subtle tabletop below
        ctx.fillStyle = '#c8ccd2';
        ctx.fillRect(0, h * 0.78, w, h * 0.22);

        // 1. Menu card on left
        const mx = w * 0.04, my = h * 0.14, mw = w * 0.29, mh = h * 0.74;
        ctx.fillStyle = '#fafafa';
        ctx.strokeStyle = '#111827';
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.roundRect(mx, my, mw, mh, 8);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#0f172a';
        ctx.textAlign = 'center';
        ctx.font = `700 ${Math.round(w * 0.036)}px Manrope, sans-serif`;
        ctx.fillText('MENU', mx + mw / 2, my + mh * 0.14);
        ctx.font = `600 ${Math.round(w * 0.025)}px Manrope, sans-serif`;
        ctx.fillText('Fried rice 60', mx + mw / 2, my + mh * 0.34);
        ctx.fillText('Tom yum 80', mx + mw / 2, my + mh * 0.43);
        ctx.fillText('Tea 30', mx + mw / 2, my + mh * 0.52);

        // 2. Dark blue OPEN sign top right
        const sx = w * 0.39, sy = h * 0.07, sw = w * 0.49, sh = h * 0.17;
        ctx.fillStyle = '#0d2659';
        ctx.strokeStyle = '#081430';
        ctx.beginPath();
        ctx.roundRect(sx, sy, sw, sh, 8);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#ffffff';
        ctx.font = `700 ${Math.round(w * 0.034)}px Manrope, sans-serif`;
        ctx.fillText('OPEN', sx + sw / 2, sy + sh * 0.44);
        ctx.fillText('9 AM - 8 PM', sx + sw / 2, sy + sh * 0.78);

        // Helper for bottles
        const drawBottle = (bx, bodyColor, lines) => {
          const bw = w * 0.19;
          const by = h * 0.39;
          const bh = h * 0.50;
          // Neck
          ctx.fillStyle = bodyColor;
          ctx.strokeStyle = '#111827';
          ctx.lineWidth = 2.5;
          ctx.fillRect(bx + bw * 0.28, by - h * 0.08, bw * 0.44, h * 0.09);
          ctx.strokeRect(bx + bw * 0.28, by - h * 0.08, bw * 0.44, h * 0.09);
          // Cap
          ctx.fillStyle = '#4b5563';
          ctx.fillRect(bx + bw * 0.25, by - h * 0.11, bw * 0.50, h * 0.04);
          ctx.strokeRect(bx + bw * 0.25, by - h * 0.11, bw * 0.50, h * 0.04);
          // Body
          ctx.fillStyle = bodyColor;
          ctx.beginPath();
          ctx.roundRect(bx, by, bw, bh, 38);
          ctx.fill();
          ctx.stroke();
          // White label
          const lx = bx + bw * 0.06, ly = by + bh * 0.31, lw = bw * 0.88, lh = bh * 0.38;
          ctx.fillStyle = '#ffffff';
          ctx.fillRect(lx, ly, lw, lh);
          ctx.strokeRect(lx, ly, lw, lh);
          ctx.fillStyle = '#0f172a';
          ctx.font = `700 ${Math.round(w * 0.022)}px Manrope, sans-serif`;
          lines.forEach((line, idx) => {
            ctx.fillText(line, lx + lw / 2, ly + lh * (0.30 + idx * 0.26));
          });
        };

        drawBottle(w * 0.41, '#4c8c64', ['SPRING', 'WATER', '500 ml']);
        drawBottle(w * 0.70, '#ef9243', ['ORANGE', 'JUICE', '250 ml']);
      }
    },

    desk: {
      id: 'desk',
      defaultPromptTh: 'ช่วยหากุญแจ',
      defaultPromptEn: 'Help me find my keys',
      summaryTh: 'บนโต๊ะทำงานมีหน้าจอโน้ตบุ๊กด้านบน ขวดน้ำดื่มวางอยู่ตรงกลาง แก้วกาแฟด้านซ้าย ขวดวิตามินซีด้านขวา และพวงกุญแจวางอยู่มุมขวาล่าง',
      summaryEn: 'On the desk there is a laptop screen at the top, a water bottle in the center, a coffee mug on the left, a Vitamin C bottle on the right, and a keyring at the lower right.',
      sources: [
        {
          id: 0,
          kind: 'screen',
          kindTh: 'หน้าจอ',
          kindEn: 'Screen',
          posTh: 'ส่วนบน',
          posEn: 'Top',
          rect: { x: 0.24, y: 0.08, w: 0.52, h: 0.25 },
          text: 'Meeting at 14:30\nRoom 402 · Design Review',
          summaryTh: 'หน้าจอแจ้งเตือนนัดประชุมเวลา 14:30 น. ที่ห้อง 402 เรื่อง Design Review',
          summaryEn: 'Screen reminder for a Design Review meeting at 14:30 in Room 402.',
          depth: 0.82
        },
        {
          id: 1,
          kind: 'bottle_label',
          kindTh: 'ฉลากขวด',
          kindEn: 'Bottle label',
          posTh: 'ตรงกลาง',
          posEn: 'Center',
          rect: { x: 0.41, y: 0.48, w: 0.18, h: 0.20 },
          text: 'DRINKING\nWATER\n600 ml',
          summaryTh: 'ฉลากขวดน้ำดื่มตรงกลางโต๊ะ ขนาด 600 มิลลิลิตร',
          summaryEn: 'Drinking water bottle label in the center, 600 ml.',
          depth: 0.68
        },
        {
          id: 2,
          kind: 'package_label',
          kindTh: 'ฉลากสินค้า',
          kindEn: 'Package label',
          posTh: 'ตรงกลาง · ขวา',
          posEn: 'Center · Right',
          rect: { x: 0.68, y: 0.38, w: 0.24, h: 0.24 },
          text: 'VITAMIN C\n1000 mg\nวันละ 1 เม็ด หลังอาหารเช้า',
          summaryTh: 'ฉลากวิตามินซี 1000 มิลลิกรัม รับประทานวันละ 1 เม็ด หลังอาหารเช้า',
          summaryEn: 'Vitamin C 1000 mg label: take 1 tablet daily after breakfast.',
          depth: 0.62
        }
      ],
      objects: [
        {
          keywords: ['ขวดน้ำ', 'น้ำดื่ม', 'water', 'bottle'],
          nameTh: 'ขวดน้ำดื่ม',
          nameEn: 'The water bottle',
          rect: { x: 0.41, y: 0.36, w: 0.18, h: 0.44 },
          point: { x: 0.50, y: 0.54 },
          depth: 0.68,
          centered: true,
          dirTh: 'กลาง',
          dirEn: 'center'
        },
        {
          keywords: ['กุญแจ', 'พวงกุญแจ', 'key', 'keys'],
          nameTh: 'พวงกุญแจ',
          nameEn: 'The keys',
          rect: { x: 0.68, y: 0.70, w: 0.22, h: 0.18 },
          point: { x: 0.78, y: 0.78 },
          depth: 0.48,
          centered: false,
          dirTh: 'ขวาล่าง',
          dirEn: 'lower right'
        },
        {
          keywords: ['แก้ว', 'กาแฟ', 'mug', 'coffee', 'cup'],
          nameTh: 'แก้วกาแฟ',
          nameEn: 'The coffee mug',
          rect: { x: 0.08, y: 0.48, w: 0.20, h: 0.26 },
          point: { x: 0.18, y: 0.60 },
          depth: 0.55,
          centered: false,
          dirTh: 'ซ้าย',
          dirEn: 'left'
        },
        {
          keywords: ['ยา', 'วิตามิน', 'ขวดยา', 'vitamin', 'medicine'],
          nameTh: 'ขวดวิตามินซี',
          nameEn: 'The Vitamin C bottle',
          rect: { x: 0.68, y: 0.36, w: 0.24, h: 0.28 },
          point: { x: 0.80, y: 0.50 },
          depth: 0.62,
          centered: false,
          dirTh: 'ขวา',
          dirEn: 'right'
        }
      ],
      draw(ctx, w, h) {
        // Warm wooden desk surface
        ctx.fillStyle = '#1e2638';
        ctx.fillRect(0, 0, w, h * 0.36);
        ctx.fillStyle = '#cfc2ad';
        ctx.fillRect(0, h * 0.36, w, h * 0.64);

        // Laptop screen at top center
        const lx = w * 0.24, ly = h * 0.08, lw = w * 0.52, lh = h * 0.25;
        ctx.fillStyle = '#0f172a';
        ctx.strokeStyle = '#64748b';
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.roundRect(lx, ly, lw, lh, 8);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#e2e8f0';
        ctx.textAlign = 'center';
        ctx.font = `700 ${Math.round(w * 0.025)}px Manrope, sans-serif`;
        ctx.fillText('Meeting at 14:30', lx + lw / 2, ly + lh * 0.44);
        ctx.fillStyle = '#93c5fd';
        ctx.font = `500 ${Math.round(w * 0.021)}px Manrope, sans-serif`;
        ctx.fillText('Room 402 · Design Review', lx + lw / 2, ly + lh * 0.72);

        // Coffee mug on left
        ctx.fillStyle = '#7c2d12';
        ctx.strokeStyle = '#1f2937';
        ctx.beginPath();
        ctx.roundRect(w * 0.09, h * 0.50, w * 0.17, h * 0.22, 16);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#fff7ed';
        ctx.font = `600 ${Math.round(w * 0.02)}px Manrope, sans-serif`;
        ctx.fillText('COFFEE', w * 0.175, h * 0.62);

        // Center Water Bottle
        const bx = w * 0.41, by = h * 0.38, bw = w * 0.18, bh = h * 0.42;
        ctx.fillStyle = '#38bdf8';
        ctx.beginPath();
        ctx.roundRect(bx, by, bw, bh, 28);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(bx + bw * 0.08, by + bh * 0.25, bw * 0.84, bh * 0.42);
        ctx.strokeRect(bx + bw * 0.08, by + bh * 0.25, bw * 0.84, bh * 0.42);
        ctx.fillStyle = '#0f172a';
        ctx.font = `700 ${Math.round(w * 0.02)}px Manrope, sans-serif`;
        ctx.fillText('DRINKING', bx + bw / 2, by + bh * 0.40);
        ctx.fillText('WATER', bx + bw / 2, by + bh * 0.51);
        ctx.fillText('600 ml', bx + bw / 2, by + bh * 0.61);

        // Vitamin C bottle on right
        const vx = w * 0.68, vy = h * 0.38, vw = w * 0.24, vh = h * 0.24;
        ctx.fillStyle = '#f59e0b';
        ctx.beginPath();
        ctx.roundRect(vx, vy, vw, vh, 14);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(vx + vw * 0.06, vy + vh * 0.18, vw * 0.88, vh * 0.68);
        ctx.fillStyle = '#111827';
        ctx.font = `700 ${Math.round(w * 0.02)}px Manrope, sans-serif`;
        ctx.fillText('VITAMIN C', vx + vw / 2, vy + vh * 0.40);
        ctx.fillText('1000 mg', vx + vw / 2, vy + vh * 0.58);
        ctx.font = `600 ${Math.round(w * 0.016)}px "Noto Sans Thai", sans-serif`;
        ctx.fillText('วันละ 1 เม็ด หลังอาหารเช้า', vx + vw / 2, vy + vh * 0.76);

        // Keys on lower right
        const kx = w * 0.75, ky = h * 0.77;
        ctx.strokeStyle = '#b45309';
        ctx.lineWidth = 5;
        ctx.beginPath();
        ctx.arc(kx, ky, w * 0.035, 0, Math.PI * 2);
        ctx.stroke();
        ctx.fillStyle = '#d97706';
        ctx.fillRect(kx + w * 0.03, ky - 4, w * 0.08, 9);
        ctx.fillRect(kx + w * 0.09, ky + 4, 7, 10);
        ctx.fillStyle = '#111827';
        ctx.font = `600 ${Math.round(w * 0.019)}px "Noto Sans Thai", sans-serif`;
        ctx.fillText('พวงกุญแจ', kx + w * 0.04, ky + h * 0.08);
      }
    },

    document: {
      id: 'document',
      defaultPromptTh: 'งบประมาณจัดงานเท่าไหร่?',
      defaultPromptEn: 'What is the event budget?',
      summaryTh: 'เอกสารนัดประชุมโครงการวันศุกร์ เวลา 10 โมง เพื่อทบทวนความคืบหน้าและแผนงาน (ให้นำรายงานโครงการมาด้วย) ส่วนด้านล่างระบุงบประมาณจัดงาน 9,000 บาท และให้ส่งเอกสารภายในวันจันทร์',
      summaryEn: 'Project meeting notice for Friday at 10 AM to review progress and plans (bring the project report). The bottom section lists an event budget of 9,000 THB and a Monday deadline for documents.',
      sources: [
        {
          id: 0,
          kind: 'document',
          kindTh: 'เอกสาร',
          kindEn: 'Document',
          posTh: 'ส่วนบน',
          posEn: 'Top',
          rect: { x: 0.06, y: 0.09, w: 0.88, h: 0.25 },
          text: 'ประชุมโครงการวันศุกร์ เวลา 10 โมง\nหัวข้อ: ทบทวนความคืบหน้าและแผนงาน\nให้นำรายงานโครงการมาด้วย',
          summaryTh: 'นัดประชุมโครงการวันศุกร์ เวลา 10:00 น. เรื่องทบทวนความคืบหน้าและแผนงาน โดยให้นำรายงานโครงการมาด้วย',
          summaryEn: 'Project meeting on Friday at 10 AM to review progress and plans; bring the project report.',
          depth: 0.42
        },
        {
          id: 1,
          kind: 'document',
          kindTh: 'เอกสาร',
          kindEn: 'Document',
          posTh: 'ส่วนล่าง',
          posEn: 'Bottom',
          rect: { x: 0.06, y: 0.68, w: 0.78, h: 0.18 },
          text: 'งบประมาณจัดงาน 9,000 บาท\nส่งเอกสารภายในวันจันทร์',
          summaryTh: 'งบประมาณจัดงานอยู่ที่ 9,000 บาท และต้องส่งเอกสารภายในวันจันทร์',
          summaryEn: 'The event budget is 9,000 THB and documents must be submitted by Monday.',
          depth: 0.40
        }
      ],
      objects: [
        {
          keywords: ['เอกสาร', 'กระดาษ', 'รายงาน', 'document', 'paper', 'page'],
          nameTh: 'แผ่นเอกสารตรงกลางภาพ',
          nameEn: 'The document page',
          rect: { x: 0.04, y: 0.05, w: 0.92, h: 0.90 },
          point: { x: 0.50, y: 0.50 },
          depth: 0.41,
          centered: true,
          dirTh: 'กลาง',
          dirEn: 'center'
        }
      ],
      draw(ctx, w, h) {
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, w, h);
        ctx.fillStyle = '#0f172a';
        ctx.textAlign = 'left';
        ctx.font = `600 ${Math.round(w * 0.036)}px "Noto Sans Thai", Manrope, sans-serif`;
        ctx.fillText('ประชุมโครงการวันศุกร์ เวลา 10 โมง', w * 0.07, h * 0.14);
        ctx.fillText('หัวข้อ: ทบทวนความคืบหน้าและแผนงาน', w * 0.07, h * 0.21);
        ctx.fillText('ให้นำรายงานโครงการมาด้วย', w * 0.07, h * 0.28);

        ctx.fillText('งบประมาณจัดงาน 9,000 บาท', w * 0.07, h * 0.74);
        ctx.fillText('ส่งเอกสารภายในวันจันทร์', w * 0.07, h * 0.81);
      }
    },

    simulator: {
      id: 'simulator',
      defaultPromptTh: 'อ่านข้อความ',
      defaultPromptEn: 'Read text',
      summaryTh: 'ภาพทดสอบประกอบด้วยข้อความด้านบน “TOP: Meeting Friday at 10 AM” วงกลมสีแดงด้านซ้ายบน สี่เหลี่ยมสีน้ำเงินด้านขวาล่าง และข้อความด้านล่าง “BOTTOM: Bring the project report”',
      summaryEn: 'Simulator sample photo with top text “TOP: Meeting Friday at 10 AM”, a red circle at the upper left, a blue square at the lower right, and bottom text “BOTTOM: Bring the project report”.',
      sources: [
        {
          id: 0,
          kind: 'other',
          kindTh: 'ข้อความ',
          kindEn: 'Text',
          posTh: 'ส่วนบน · ซ้าย',
          posEn: 'Top · Left',
          rect: { x: 0.04, y: 0.05, w: 0.78, h: 0.08 },
          text: 'TOP: Meeting Friday at 10 AM',
          summaryTh: 'นัดประชุมวันศุกร์ เวลา 10:00 น. (Meeting Friday at 10 AM)',
          summaryEn: 'Meeting scheduled for Friday at 10 AM.',
          depth: 1.15
        },
        {
          id: 1,
          kind: 'other',
          kindTh: 'ข้อความ',
          kindEn: 'Text',
          posTh: 'ส่วนล่าง',
          posEn: 'Bottom',
          rect: { x: 0.04, y: 0.87, w: 0.84, h: 0.08 },
          text: 'BOTTOM: Bring the project report',
          summaryTh: 'ให้นำรายงานโครงการมาด้วย (Bring the project report)',
          summaryEn: 'Reminder to bring the project report.',
          depth: 1.10
        }
      ],
      objects: [
        {
          keywords: ['วงกลม', 'สีแดง', 'red', 'circle'],
          nameTh: 'วงกลมสีแดง',
          nameEn: 'The red circle',
          rect: { x: 0.12, y: 0.19, w: 0.30, h: 0.30 },
          point: { x: 0.27, y: 0.34 },
          depth: 1.20,
          centered: false,
          dirTh: 'ซ้ายบน',
          dirEn: 'upper left'
        },
        {
          keywords: ['สี่เหลี่ยม', 'สีน้ำเงิน', 'สีฟ้า', 'blue', 'square'],
          nameTh: 'สี่เหลี่ยมสีน้ำเงิน',
          nameEn: 'The blue square',
          rect: { x: 0.57, y: 0.54, w: 0.29, h: 0.29 },
          point: { x: 0.71, y: 0.68 },
          depth: 1.50,
          centered: false,
          dirTh: 'ขวาล่าง',
          dirEn: 'lower right'
        }
      ],
      draw(ctx, w, h) {
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, w, h);
        // Red circle
        ctx.fillStyle = '#ff3b30';
        ctx.beginPath();
        ctx.arc(w * 0.27, h * 0.34, w * 0.15, 0, Math.PI * 2);
        ctx.fill();
        // Blue square
        ctx.fillStyle = '#007aff';
        ctx.fillRect(w * 0.57, h * 0.54, w * 0.29, w * 0.29);
        // Text
        ctx.fillStyle = '#000000';
        ctx.textAlign = 'left';
        ctx.font = `700 ${Math.round(w * 0.038)}px Manrope, sans-serif`;
        ctx.fillText('TOP: Meeting Friday at 10 AM', w * 0.05, h * 0.10);
        ctx.fillText('BOTTOM: Bring the project report', w * 0.05, h * 0.92);
      }
    },

    walkway: {
      id: 'walkway',
      defaultPromptTh: 'เก้าอี้ด้านหน้าอยู่ห่างกี่เมตร?',
      defaultPromptEn: 'How far is the chair ahead?',
      summaryTh: 'ทางเดินในอาคาร มีป้ายทางออก EXIT ชั้น 2 ด้านบน ป้ายห้อง 204 ห้องปฏิบัติการวิจัยทางด้านซ้าย และมีเก้าอี้ขวางอยู่ตรงกลางทางเดินห่างประมาณ 0.85 เมตร',
      summaryEn: 'Indoor walkway with an EXIT Floor 2 sign at the top, a Room 204 Research Lab plaque on the left, and a chair obstacle in the center of the path about 0.85 meters ahead.',
      hasObstacle: true,
      obstacleDistance: 0.85,
      sources: [
        {
          id: 0,
          kind: 'sign',
          kindTh: 'ป้าย',
          kindEn: 'Sign',
          posTh: 'ส่วนบน',
          posEn: 'Top',
          rect: { x: 0.30, y: 0.08, w: 0.40, h: 0.13 },
          text: 'ทางออก EXIT\nชั้น 2 · Floor 2',
          summaryTh: 'ป้ายทางออก (EXIT) บริเวณชั้น 2',
          summaryEn: 'EXIT sign on Floor 2.',
          depth: 2.40
        },
        {
          id: 1,
          kind: 'sign',
          kindTh: 'ป้าย',
          kindEn: 'Sign',
          posTh: 'ตรงกลาง · ซ้าย',
          posEn: 'Center · Left',
          rect: { x: 0.06, y: 0.30, w: 0.28, h: 0.16 },
          text: 'ห้อง 204\nห้องปฏิบัติการวิจัย',
          summaryTh: 'ป้ายหน้าห้อง 204 ห้องปฏิบัติการวิจัย',
          summaryEn: 'Door plaque for Room 204, Research Laboratory.',
          depth: 1.15
        }
      ],
      objects: [
        {
          keywords: ['เก้าอี้', 'สิ่งกีดขวาง', 'ทางเดิน', 'chair', 'obstacle', 'seat'],
          nameTh: 'เก้าอี้ด้านหน้า',
          nameEn: 'The chair ahead',
          rect: { x: 0.34, y: 0.46, w: 0.32, h: 0.40 },
          point: { x: 0.50, y: 0.64 },
          depth: 0.85,
          centered: true,
          dirTh: 'กลาง',
          dirEn: 'center'
        },
        {
          keywords: ['ป้ายห้อง', '204', 'room'],
          nameTh: 'ป้ายห้อง 204',
          nameEn: 'The Room 204 sign',
          rect: { x: 0.06, y: 0.30, w: 0.28, h: 0.16 },
          point: { x: 0.20, y: 0.38 },
          depth: 1.15,
          centered: false,
          dirTh: 'ซ้าย',
          dirEn: 'left'
        }
      ],
      draw(ctx, w, h) {
        // Corridor walls & floor
        ctx.fillStyle = '#cbd5e1';
        ctx.fillRect(0, 0, w, h * 0.68);
        ctx.fillStyle = '#94a3b8';
        ctx.fillRect(0, h * 0.68, w, h * 0.32);

        // Exit sign at top
        const ex = w * 0.30, ey = h * 0.08, ew = w * 0.40, eh = h * 0.13;
        ctx.fillStyle = '#15803d';
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 2.5;
        ctx.beginPath();
        ctx.roundRect(ex, ey, ew, eh, 8);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#ffffff';
        ctx.textAlign = 'center';
        ctx.font = `700 ${Math.round(w * 0.028)}px "Noto Sans Thai", Manrope, sans-serif`;
        ctx.fillText('ทางออก EXIT', ex + ew / 2, ey + eh * 0.48);
        ctx.font = `500 ${Math.round(w * 0.022)}px "Noto Sans Thai", Manrope, sans-serif`;
        ctx.fillText('ชั้น 2 · Floor 2', ex + ew / 2, ey + eh * 0.80);

        // Room 204 plaque on left
        const rx = w * 0.06, ry = h * 0.30, rw = w * 0.28, rh = h * 0.16;
        ctx.fillStyle = '#1e293b';
        ctx.beginPath();
        ctx.roundRect(rx, ry, rw, rh, 8);
        ctx.fill();
        ctx.fillStyle = '#f8fafc';
        ctx.font = `700 ${Math.round(w * 0.026)}px "Noto Sans Thai", Manrope, sans-serif`;
        ctx.fillText('ห้อง 204', rx + rw / 2, ry + rh * 0.44);
        ctx.font = `500 ${Math.round(w * 0.02)}px "Noto Sans Thai", Manrope, sans-serif`;
        ctx.fillText('ห้องปฏิบัติการวิจัย', rx + rw / 2, ry + rh * 0.76);

        // Chair obstacle in center foreground
        const cx = w * 0.35, cy = h * 0.47, cw = w * 0.30, ch = h * 0.38;
        ctx.fillStyle = '#b91c1c';
        ctx.strokeStyle = '#111827';
        ctx.lineWidth = 3;
        // Backrest
        ctx.beginPath();
        ctx.roundRect(cx + cw * 0.1, cy, cw * 0.8, ch * 0.42, 10);
        ctx.fill();
        ctx.stroke();
        // Seat
        ctx.fillStyle = '#991b1b';
        ctx.beginPath();
        ctx.roundRect(cx, cy + ch * 0.42, cw, ch * 0.20, 8);
        ctx.fill();
        ctx.stroke();
        // Legs
        ctx.fillStyle = '#334155';
        ctx.fillRect(cx + cw * 0.08, cy + ch * 0.62, 10, ch * 0.36);
        ctx.fillRect(cx + cw * 0.84, cy + ch * 0.62, 10, ch * 0.36);
      }
    }
  };

  /* ==========================================================================
     3. App State (Mirrors CameraScreen, ChatViewModel & CameraSettingsSheet)
     ========================================================================== */
  const state = {
    appLang: document.documentElement.lang === 'en' ? 'en' : 'th',
    speechLang: 'th',
    sceneId: 'cafe',
    customImage: null,
    webcamStream: null,
    cameraError: false,
    depthMode: 'lidar', // 'lidar' | 'da3'
    da3Scale: 1.0,
    reusePhotoOnHold: false,
    hasCapturedPhoto: true,
    ttsEnabled: true,
    obstacleEnabled: false,
    obstacleWarnDist: 2.0,
    obstacleCloseDist: 0.4,
    obstacleMaxIntensity: 0.8,
    activeSheet: 'camera', // 'camera' | 'settings' | 'conversation' | 'region' | 'sources' | 'distance' | 'performance' | 'about'
    photoAction: 'question', // 'question' | 'read' | 'summarize'
    region: { x: 0, y: 0, w: 1, h: 1 },
    selectedSourceId: null,
    distancePoint: { x: 0.5, y: 0.58 },
    messages: [],
    currentTranscript: '',
    currentAnswer: '',
    isListening: false,
    isWorking: false,
    isSpeaking: false,
    pressStartTime: 0,
    pressTimer: null,
    answerTimer: null
  };

  /* ==========================================================================
     4. Localization Dictionary for In-App SwiftUI Elements
     ========================================================================== */
  const UI_TEXT = {
    th: {
      holdToAsk: 'กดค้างเพื่อถาม · แตะเพื่อถ่าย',
      holdReuse: 'กดค้างเพื่อถามต่อจากภาพเดิม · แตะเพื่อถ่ายใหม่',
      holdSample: 'กดค้างเพื่อลองคำถามตัวอย่าง · แตะเพื่อถ่าย',
      releaseSample: 'ปล่อยปุ่มเพื่อส่งคำถามตัวอย่าง',
      speakNow: 'พูดได้เลย · ปล่อยปุ่มเพื่อส่ง',
      transcribing: 'กำลังรับข้อความจากเบราว์เซอร์…',
      analyzing: 'กำลังดูภาพและตอบ…',
      readingAloud: 'กำลังอ่านคำตอบ · กดค้างเพื่อถามใหม่',
      photoTaken: 'เก็บภาพตัวอย่างแล้ว กดค้างเพื่อถามเกี่ยวกับภาพ',
      youAsked: 'คุณถาม',
      listening: 'กำลังฟัง…',
      openConv: 'เปิดหน้าสนทนา ›',
      lidarProvenance: 'ฉากตัวอย่าง · ระยะ LiDAR จำลอง',
      da3Provenance: 'ฉากตัวอย่าง · ระยะ Depth Anything 3 Metric จำลอง',
      mediaPreview: 'แสดงตัวอย่างเท่านั้น เลือกฉากตัวอย่างเพื่อทดลองถาม อ่านข้อความ หรือวัดระยะ',
      previewCamera: 'ดูกล้อง',
      stopCameraPreview: 'ปิดภาพจากกล้อง',
      cameraUnavailable: 'เปิดกล้องไม่ได้ ลองตรวจสิทธิ์กล้องในเบราว์เซอร์',
      obsClear: 'ไม่พบสิ่งกีดขวางในบริเวณที่วัด',
      obsWarning: 'พบสิ่งกีดขวางด้านหน้ากล้อง · กำลังสั่นเตือน',
      obsOff: 'ปิดการเตือนอยู่',
      settingsTitle: 'ตั้งค่า',
      done: 'เสร็จ',
      cancel: 'ยกเลิก',
      back: 'กลับ',
      brandSub: 'ปรับให้พร้อมในแบบของคุณ',
      appLangHeading: 'ภาษาแอพ',
      appLangNote: 'เปลี่ยนเฉพาะภาษาหน้าจอ ไม่เปลี่ยนภาษารับเสียงหรือคำตอบ',
      speechHeading: 'ภาษาและคำถาม',
      speechSub: 'เลือกภาษาที่คุณใช้พูดกับ LunaV',
      speechStatus: 'เลือกเปิดการรับเสียงผ่านเบราว์เซอร์ได้ที่หน้าเดโม',
      reuseLabel: 'ใช้ภาพเดิมเมื่อกดค้าง',
      reuseNote: 'กดค้างเพื่อถามต่อจากภาพล่าสุด แตะสั้นเพื่อถ่ายใหม่ คำสั่งช่วยหาของจะถ่ายภาพใหม่',
      holdNote: 'กดปุ่มกลางค้างแล้วพูด ปล่อยเพื่อส่งคำถาม\nแตะสั้นเพื่อถ่ายภาพอย่างเดียว',
      prepSpeechBtn: 'เตรียม / ลองระบบเสียงอีกครั้ง',
      aboutSpeechSum: 'เกี่ยวกับการรับเสียง',
      ttsHeading: 'เสียงอ่านคำตอบ',
      ttsSub: 'ฟังคำตอบด้วยเสียงของเบราว์เซอร์',
      ttsToggle: 'อ่านคำตอบอัตโนมัติ',
      voiceThLbl: 'เสียงภาษาไทย',
      voiceEnLbl: 'เสียงภาษาอังกฤษ',
      previewTts: 'ลองฟังเสียง',
      stopTts: 'หยุดอ่าน',
      ttsReady: 'ใช้เสียงที่เบราว์เซอร์มีให้',
      obsHeading: 'สั่นเตือนสิ่งกีดขวาง',
      obsToggle: 'เตือนด้วย LiDAR',
      obsStartLbl: 'ระยะเริ่มเตือน',
      obsCloseLbl: 'ระยะสั่นแรงที่สุด',
      obsIntLbl: 'ความแรงสูงสุด',
      obsTestBtn: 'ทดสอบการสั่น',
      toolsHeading: 'เครื่องมือทดสอบ',
      toolsSub: 'ใช้ภาพล่าสุด เลือกพื้นที่หรือพิมพ์ถามได้เอง',
      toolSample: 'ใช้ภาพทดสอบ',
      toolImport: 'เลือกรูปจากคลังภาพ',
      toolAsk: 'ถามเกี่ยวกับภาพ',
      toolRead: 'อ่านข้อความและเลือกพื้นที่',
      toolSum: 'สรุปป้าย เมนู และฉลาก',
      toolLidar: 'ทดสอบระยะและเลือกจุดเอง',
      sysHeading: 'ระบบและความพร้อม',
      sysReady: 'พร้อมทดลองกับฉากตัวอย่าง',
      sysDepthLbl: 'ระยะจากกล้องหลัง',
      clearCtxBtn: 'ล้างบริบท / เริ่มถามใหม่',
      perfBtn: 'ข้อมูลโมเดล เครื่อง และ LiDAR',
      privacyNote: 'รูปและกล้องใช้แสดงตัวอย่างในหน้านี้ การรับเสียงเป็นตัวเลือกของเบราว์เซอร์',
      aboutHeading: 'เกี่ยวกับ',
      openAboutBtn: 'เกี่ยวกับ LunaV',
      convTitle: 'ภาพและข้อความ',
      convReady: 'พร้อมถามเกี่ยวกับภาพนี้',
      modeQuestion: 'ถามภาพ',
      modeRead: 'อ่านข้อความ',
      modeSummarize: 'สรุปข้อความ',
      wholePhoto: 'ทั้งภาพ',
      selectedRegion: 'กรอบที่เลือก',
      tapToSelectRegion: 'แตะเพื่อเลือกพื้นที่ข้อความ',
      askDistHint: 'ถามระยะได้เลย · AI เลือกวัตถุอัตโนมัติ',
      choosePoint: 'เลือกจุดเอง',
      discoverSources: 'แยกป้าย เมนู และฉลากในภาพ',
      chooseFromGroups: n => `เลือกจากข้อความ ${n} กลุ่ม`,
      emptyAskTitle: 'อยากรู้อะไรจากภาพนี้?',
      emptyReadTitle: 'อ่านตามข้อความในภาพ',
      emptySumTitle: 'เก็บใจความสำคัญให้สั้นลง',
      emptyAskChip: 'ในภาพมีอะไรบ้าง?',
      emptyReadDesc: 'อ่านทั้งภาพเพื่อแยกข้อความเป็นกลุ่ม หรือแตะแยกป้าย เมนู และฉลากเพื่อเลือกเฉพาะชิ้น',
      emptySumDesc: 'เลือกพื้นที่แล้วกดสรุปข้อความ หรือพิมพ์เรื่องที่อยากให้เน้นด้านล่าง',
      placeholderAsk: 'พิมพ์ถามเกี่ยวกับภาพ…',
      placeholderSum: 'เน้นเรื่องใดเป็นพิเศษ? (ไม่บังคับ)',
      processedOnDevice: 'คำตอบจากข้อมูลฉากตัวอย่าง',
      checkTextNote: 'ตรวจทานข้อความกับภาพก่อนนำไปใช้',
      regionTitle: 'เลือกพื้นที่ข้อความ',
      useThisRegion: 'ใช้พื้นที่นี้',
      dragRegionGuide: 'ลากกรอบรอบข้อความที่ต้องการ',
      dragRegionSub: 'แอพจะอ่านหรือสรุปเฉพาะในกรอบนี้',
      top: 'ส่วนบน',
      middle: 'ตรงกลาง',
      bottom: 'ส่วนล่าง',
      left: 'ซ้าย',
      right: 'ขวา',
      selectedPrefix: 'เลือกแล้ว: ',
      sourcesTitle: 'ข้อความแต่ละจุด',
      sourcesLead: 'แตะกลุ่มที่ต้องการอ่านหรือสรุป',
      distTitleLidar: 'วัดระยะ LiDAR',
      distTitleDa3: 'ประเมินระยะจากภาพ',
      useThisPoint: 'ใช้จุดนี้',
      tapObjectDist: 'แตะวัตถุที่จะวัดระยะ',
      chooseCenter: 'เลือกจุดกลางภาพ',
      metersUnit: 'เมตร',
      summarizeGroup: 'สรุปกลุ่มนี้',
      copyBtn: 'คัดลอก',
      copiedBtn: 'คัดลอกแล้ว'
    },
    en: {
      holdToAsk: 'Hold to ask · Tap to take a photo',
      holdReuse: 'Hold to ask about the same photo · Tap to take a new one',
      holdSample: 'Hold for a sample question · Tap to take a photo',
      releaseSample: 'Release to send the sample question',
      speakNow: 'Speak now · Release to send',
      transcribing: 'Getting text from the browser…',
      analyzing: 'Analyzing the photo and answering…',
      readingAloud: 'Reading the answer · Hold to ask again',
      photoTaken: 'Sample captured. Hold to ask about the photo.',
      youAsked: 'You asked',
      listening: 'Listening…',
      openConv: 'Conversation ›',
      lidarProvenance: 'Sample scene · Simulated LiDAR distance',
      da3Provenance: 'Sample scene · Simulated Depth Anything 3 Metric distance',
      mediaPreview: 'Preview only. Choose a sample scene to try questions, text reading, or distance.',
      previewCamera: 'Preview camera',
      stopCameraPreview: 'Stop camera preview',
      cameraUnavailable: 'Couldn’t open the camera. Check your browser’s camera permissions.',
      obsClear: 'No obstacle detected in the measured area',
      obsWarning: 'Obstacle ahead of the camera · vibrating',
      obsOff: 'Alerts are off',
      settingsTitle: 'Settings',
      done: 'Done',
      cancel: 'Cancel',
      back: 'Back',
      brandSub: 'Make LunaV work your way',
      appLangHeading: 'App language',
      appLangNote: 'Changes the interface language only. Speech and answer language settings stay the same.',
      speechHeading: 'Speech and questions',
      speechSub: 'Choose the language you speak to LunaV',
      speechStatus: 'You can enable browser speech input on the demo page',
      reuseLabel: 'Reuse the photo on hold',
      reuseNote: 'Hold to ask about the latest photo. Tap to take a new one. Find-object requests take a fresh photo.',
      holdNote: 'Hold the center button and speak. Release to send your question.\nTap briefly to take a photo.',
      prepSpeechBtn: 'Prepare / Retry speech',
      aboutSpeechSum: 'About speech recognition',
      ttsHeading: 'Spoken answers',
      ttsSub: 'Listen to answers with a browser voice',
      ttsToggle: 'Read answers aloud automatically',
      voiceThLbl: 'Thai voice',
      voiceEnLbl: 'English voice',
      previewTts: 'Preview voice',
      stopTts: 'Stop reading',
      ttsReady: 'Uses voices available in your browser',
      obsHeading: 'Obstacle vibration alerts',
      obsToggle: 'LiDAR proximity alerts',
      obsStartLbl: 'Start warning at',
      obsCloseLbl: 'Strongest vibration at',
      obsIntLbl: 'Maximum intensity',
      obsTestBtn: 'Test vibration',
      toolsHeading: 'Testing tools',
      toolsSub: 'Use the latest photo, select a region, or type a question',
      toolSample: 'Use sample photo',
      toolImport: 'Choose from photo library',
      toolAsk: 'Ask about the photo',
      toolRead: 'Read text and select a region',
      toolSum: 'Summarize signs, menus, and labels',
      toolLidar: 'Test depth and choose a point',
      sysHeading: 'System and readiness',
      sysReady: 'Ready to try with sample scenes',
      sysDepthLbl: 'Rear-camera depth',
      clearCtxBtn: 'Clear context / Start again',
      perfBtn: 'Model, device, and LiDAR details',
      privacyNote: 'Your photos and camera are previewed on this page. Browser speech input is optional.',
      aboutHeading: 'About',
      openAboutBtn: 'About LunaV',
      convTitle: 'Photo and text',
      convReady: 'Ready for questions about this photo',
      modeQuestion: 'Ask about photo',
      modeRead: 'Read text',
      modeSummarize: 'Summarize text',
      wholePhoto: 'Whole photo',
      selectedRegion: 'Selected region',
      tapToSelectRegion: 'Tap to select a text region',
      askDistHint: 'Ask about distance · AI selects the object',
      choosePoint: 'Choose a point',
      discoverSources: 'Find signs, menus, and labels',
      chooseFromGroups: n => `Choose from ${n} text groups`,
      emptyAskTitle: 'What would you like to know about this photo?',
      emptyReadTitle: 'Read the text in the photo',
      emptySumTitle: 'Summarize the key points',
      emptyAskChip: 'What is in this photo?',
      emptyReadDesc: 'Read the whole photo to find text groups, or find signs, menus, and labels to choose one item',
      emptySumDesc: 'Select a region and tap Summarize text, or type what to focus on below',
      placeholderAsk: 'Ask a question about the photo…',
      placeholderSum: 'Anything to focus on? (optional)',
      processedOnDevice: 'Answers use the sample scene’s data',
      checkTextNote: 'Check the text against the photo before using it',
      regionTitle: 'Select a text region',
      useThisRegion: 'Use this region',
      dragRegionGuide: 'Drag a box around the text you want',
      dragRegionSub: 'LunaV will read or summarize only within this box',
      top: 'Top',
      middle: 'Center',
      bottom: 'Bottom',
      left: 'Left',
      right: 'Right',
      selectedPrefix: 'Selected: ',
      sourcesTitle: 'Text groups',
      sourcesLead: 'Tap a group to read or summarize',
      distTitleLidar: 'Measure LiDAR depth',
      distTitleDa3: 'Estimate depth from photo',
      useThisPoint: 'Use this point',
      tapObjectDist: 'Tap an object to measure',
      chooseCenter: 'Choose the center point',
      metersUnit: 'meters',
      summarizeGroup: 'Summarize this group',
      copyBtn: 'Copy',
      copiedBtn: 'Copied'
    }
  };

  const t = () => UI_TEXT[state.appLang] || UI_TEXT.th;
  const currentScene = () => SCENES[state.sceneId] || SCENES.cafe;
  const isMediaPreview = () => Boolean(state.customImage || state.webcamStream);
  const browserSpeechEnabled = () => Boolean(document.getElementById('demo-voice-input')?.checked &&
    (window.SpeechRecognition || window.webkitSpeechRecognition));
  let mediaRequest = 0;

  /* ==========================================================================
     5. Sound & Haptic Helpers (ObjectCentered.wav + Web Audio + Vibration)
     ========================================================================== */
  const centeredAudio = new Audio('assets/object-centered.wav');
  centeredAudio.preload = 'auto';

  function playCenteredCue() {
    triggerHapticBuzz();
    centeredAudio.currentTime = 0;
    centeredAudio.play().catch(() => {
      // Fallback Web Audio chime if autoplay blocked
      try {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        if (!Ctx) return;
        const actx = new Ctx();
        const osc = actx.createOscillator();
        const gain = actx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(880, actx.currentTime);
        osc.frequency.exponentialRampToValueAtTime(1320, actx.currentTime + 0.16);
        gain.gain.setValueAtTime(0.18, actx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, actx.currentTime + 0.18);
        osc.connect(gain);
        gain.connect(actx.destination);
        osc.start();
        osc.stop(actx.currentTime + 0.18);
      } catch { /* ignore */ }
    });
  }

  function triggerHapticBuzz() {
    const frame = document.getElementById('iphone-frame');
    if (frame) {
      frame.classList.remove('is-vibrating');
      void frame.offsetWidth;
      frame.classList.add('is-vibrating');
    }
    if (navigator.vibrate) {
      try { navigator.vibrate([60, 40, 90]); } catch { /* ignore */ }
    }
  }

  function speakAnswer(text) {
    if (!state.ttsEnabled || !('speechSynthesis' in window) || !text) return;
    try {
      window.speechSynthesis.cancel();
      const utter = new SpeechSynthesisUtterance(text.replace(/\[.*?\]/g, ''));
      const hasThai = /[\u0E00-\u0E7F]/.test(text);
      utter.lang = hasThai ? 'th-TH' : 'en-US';
      utter.rate = 1.02;
      const di = document.getElementById('dynamic-island');
      const stopBtn = document.getElementById('stopAnswerSpeech');
      utter.onstart = () => {
        state.isSpeaking = true;
        di?.classList.add('is-active', 'is-speaking');
        if (stopBtn) stopBtn.hidden = false;
        updateCameraStatus();
      };
      utter.onend = utter.onerror = () => {
        state.isSpeaking = false;
        di?.classList.remove('is-active', 'is-speaking');
        if (stopBtn) stopBtn.hidden = true;
        updateCameraStatus();
      };
      window.speechSynthesis.speak(utter);
    } catch { /* ignore */ }
  }

  function stopSpeaking() {
    if ('speechSynthesis' in window) {
      try { window.speechSynthesis.cancel(); } catch { /* ignore */ }
    }
    state.isSpeaking = false;
    document.getElementById('dynamic-island')?.classList.remove('is-active', 'is-speaking');
    const stopBtn = document.getElementById('stopAnswerSpeech');
    if (stopBtn) stopBtn.hidden = true;
    updateCameraStatus();
  }

  /* ==========================================================================
     6. Canvas Rendering (Main Camera, Thumbnails, Region Crop & Distance Map)
     ========================================================================== */
  const mainCanvas = document.getElementById('app-photo-canvas');
  const mainCtx = mainCanvas?.getContext('2d');

  function drawSceneToCanvas(canvas, options = {}) {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    if (isMediaPreview()) {
      ctx.fillStyle = '#080f20';
      ctx.fillRect(0, 0, w, h);
      if (state.customImage) {
        const scale = Math.min(w / state.customImage.width, h / state.customImage.height);
        const dw = state.customImage.width * scale;
        const dh = state.customImage.height * scale;
        ctx.drawImage(state.customImage, (w - dw) / 2, (h - dh) / 2, dw, dh);
      }
      return;
    }
    currentScene().draw(ctx, w, h);

    // Optional region crop overlay
    if (options.regionOverlay) {
      const r = options.regionOverlay;
      ctx.save();
      ctx.fillStyle = 'rgba(8, 15, 32, 0.62)';
      ctx.beginPath();
      ctx.rect(0, 0, w, h);
      ctx.rect(r.x * w, r.y * h, r.w * w, r.h * h);
      ctx.fill('evenodd');
      ctx.strokeStyle = '#dac7a0';
      ctx.lineWidth = Math.max(2, w * 0.006);
      ctx.strokeRect(r.x * w, r.y * h, r.w * w, r.h * h);
      ctx.restore();
    }

    // Optional distance target overlay
    if (options.distancePoint) {
      const pt = options.distancePoint;
      const px = pt.x * w;
      const py = pt.y * h;
      ctx.save();
      ctx.strokeStyle = '#dac7a0';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.arc(px, py, 14, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = '#dac7a0';
      ctx.beginPath();
      ctx.arc(px, py, 3.5, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
  }

  function renderAllCanvases() {
    drawSceneToCanvas(mainCanvas);
    drawSceneToCanvas(document.getElementById('conv-mini-thumb'));
    drawSceneToCanvas(document.getElementById('conv-region-thumb'), { regionOverlay: state.region });
    drawSceneToCanvas(document.getElementById('regionCanvas'), { regionOverlay: state.region });
    drawSceneToCanvas(document.getElementById('sourcesMapCanvas'));
    drawSceneToCanvas(document.getElementById('distanceCanvas'), { distancePoint: state.distancePoint });
    renderSourcesOverlay();
    updateDistanceSheetReadout();
    updateObstacleStatus();
  }

  /* ==========================================================================
     7. Pipeline Stage Indicator
     ========================================================================== */
  function setActivePipelineStage(stageKey) {
    document.querySelectorAll('#pipeline-steps .pipe-step').forEach(el => {
      el.classList.toggle('is-active', el.dataset.pipe === stageKey);
    });
  }

  /* ==========================================================================
     8. Smart Question & Action Engine (Mirrors ChatViewModel & Shared Swift)
     ========================================================================== */
  function getRegionLabel(rect) {
    const L = t();
    if (rect.x <= 0.02 && rect.y <= 0.02 && rect.w >= 0.96 && rect.h >= 0.96) {
      return L.wholePhoto;
    }
    const midY = rect.y + rect.h / 2;
    const midX = rect.x + rect.w / 2;
    const vert = midY < 0.34 ? L.top : midY > 0.66 ? L.bottom : L.middle;
    const horiz = midX < 0.34 ? L.left : midX > 0.66 ? L.right : '';
    return horiz ? `${vert} · ${horiz}` : vert;
  }

  function getSourceTitle(src) {
    const isEn = state.appLang === 'en';
    const kind = isEn ? src.kindEn : src.kindTh;
    const pos = isEn ? src.posEn : src.posTh;
    return `${kind} ${src.id + 1} · ${pos}`;
  }

  function sampleDepthAtPoint(pt) {
    const scene = currentScene();
    for (const obj of scene.objects || []) {
      const r = obj.rect;
      if (pt.x >= r.x && pt.x <= r.x + r.w && pt.y >= r.y && pt.y <= r.y + r.h) {
        return { meters: obj.depth, target: obj };
      }
    }
    for (const src of scene.sources || []) {
      const r = src.rect;
      if (pt.x >= r.x && pt.x <= r.x + r.w && pt.y >= r.y && pt.y <= r.y + r.h) {
        return { meters: src.depth, target: null };
      }
    }
    const fallback = 0.65 + (1 - pt.y) * 0.95;
    return { meters: fallback, target: null };
  }

  function findNamedObject(question, objects) {
    let best = null;
    let bestLength = 0;
    for (const object of objects) {
      for (const keyword of object.keywords) {
        if (keyword.length > bestLength && question.includes(keyword.toLowerCase())) {
          best = object;
          bestLength = keyword.length;
        }
      }
    }
    return best;
  }

  function formatDistanceAnswer(subjectTh, subjectEn, rawMeters, inCm = false) {
    const isEn = state.appLang === 'en';
    const meters = rawMeters * (state.depthMode === 'da3' ? state.da3Scale : 1);
    if (state.depthMode === 'da3') {
      const valTh = inCm ? `${Math.round(meters * 10) * 10} เซนติเมตร` : `${meters.toFixed(1)} เมตร`;
      const valEn = inCm ? `${Math.round(meters * 10) * 10} cm` : `${meters.toFixed(1)} meters`;
      return isEn
        ? `${subjectEn} is about ${valEn} from the camera in the Depth Anything 3 Metric simulation.`
        : `${subjectTh}อยู่ห่างกล้องประมาณ ${valTh} ในการจำลอง Depth Anything 3 Metric`;
    }
    const valTh = inCm ? `${Math.round(meters * 100)} เซนติเมตร` : `${meters.toFixed(2)} เมตร`;
    const valEn = inCm ? `${Math.round(meters * 100)} cm` : `${meters.toFixed(2)} meters`;
    return isEn
      ? `${subjectEn} is about ${valEn} from the camera in the LiDAR simulation.`
      : `${subjectTh}อยู่ห่างกล้องประมาณ ${valTh} ในการจำลอง LiDAR`;
  }

  function evaluateQuestion(rawQuestion) {
    const q = (rawQuestion || '').trim();
    const qLower = q.toLowerCase();
    const scene = currentScene();
    const isEn = state.appLang === 'en' || /^[a-z0-9\s?.,'"!-]+$/i.test(q);

    // 1. Nearby Object Finder (NearbyObjectFinder.swift)
    const isFinder = /ช่วยหา|หา.*อยู่ไหน|อยู่ตรงไหน|help me find|where is|find my|find the/i.test(qLower);
    if (isFinder) {
      setActivePipelineStage('qwen');
      const matched = findNamedObject(qLower, scene.objects || []);
      if (!matched) {
        return {
          text: isEn
            ? 'I couldn’t find it in this photo. Aim the camera at another area (or switch to the Desk scene for keys) and ask again.'
            : 'ยังไม่พบของที่หาในภาพนี้ ลองเล็งกล้องไปอีกบริเวณแล้วถามใหม่ (หากต้องการหากุญแจ ลองสลับไปที่ฉาก “โต๊ะทำงาน”)',
          centeredCue: false
        };
      }
      if (matched.centered) {
        return {
          text: isEn
            ? `The object (${matched.nameEn.toLowerCase()}) is centered in this photo.`
            : `ของที่หา (${matched.nameTh}) อยู่กลางภาพนี้`,
          centeredCue: true
        };
      }
      return {
        text: isEn
          ? `The object is at the ${matched.dirEn} of this photo. Aim the camera that way and ask again.`
          : `ของที่หาอยู่ด้าน${matched.dirTh}ของภาพนี้ ลองเล็งกล้องไปทางนั้นแล้วถามอีกครั้ง`,
        centeredCue: false
      };
    }

    // 2. Distance Question (LiDARMeasurement.swift + AutomaticDistanceResolver.swift)
    const isDistance = /กี่เมตร|กี่เซน|ห่าง|ไกลแค่ไหน|ระยะ|how far|distance|meters|centimeters/i.test(qLower);
    if (isDistance) {
      setActivePipelineStage('vision');
      const inCm = /เซน|cm|centimeter/i.test(qLower);
      const matched = findNamedObject(qLower, scene.objects || []) || (scene.objects || [])[0];
      if (matched) {
        state.distancePoint = { ...matched.point };
        return {
          text: formatDistanceAnswer(matched.nameTh, matched.nameEn, matched.depth, inCm),
          distance: { point: matched.point, label: isEn ? matched.nameEn : matched.nameTh }
        };
      }
      const centerSample = sampleDepthAtPoint({ x: 0.5, y: 0.5 });
      return {
        text: formatDistanceAnswer('พื้นผิวตรงกลางภาพ', 'The center surface', centerSample.meters, inCm),
        distance: { point: { x: 0.5, y: 0.5 }, label: isEn ? 'Center point' : 'จุดกึ่งกลางภาพ' }
      };
    }

    // 3. Targeted OCR Reading (TargetedTextReading.swift)
    if (/ราคา|กี่บาท|price|cost|how much/i.test(qLower)) {
      setActivePipelineStage('vision');
      if (scene.id === 'cafe') {
        const name = /ข้าวผัด|fried rice/i.test(q) ? 'Fried rice'
          : /ต้มยำ|tom yum/i.test(q) ? 'Tom yum'
          : /(?:ราคาชา|ของชา|\btea\b)/i.test(q) ? 'Tea' : null;
        const row = scene.sources.find(source => source.kind === 'menu')?.text.split('\n')
          .find(line => name && line.startsWith(name + ' '));
        return { text: row ? (isEn ? `Price ${row.split(' ').at(-1)}` : `ราคา ${row.split(' ').at(-1)}`)
          : (isEn ? 'I found several prices. Say which item to read.' : 'พบหลายราคา ลองระบุชื่อรายการที่ต้องการอ่าน') };
      }
      if (scene.id === 'document') {
        return {
          text: isEn
            ? 'From the bottom section of the document: Event budget 9,000 THB.'
            : 'จากเอกสารส่วนล่าง: งบประมาณจัดงาน 9,000 บาท'
        };
      }
    }

    if (/กี่โมง|เวลา|เปิด|ปิด|time|hour|open|when/i.test(qLower)) {
      setActivePipelineStage('vision');
      if (scene.id === 'cafe') {
        return {
          text: isEn
            ? 'The sign at the top right reads: OPEN 9 AM - 8 PM.'
            : 'ป้ายด้านขวาบนระบุเวลาเปิดทำการ: OPEN 9 AM - 8 PM (9 โมงเช้า ถึง 2 ทุ่ม)'
        };
      }
      if (scene.id === 'document') {
        return {
          text: isEn
            ? 'Meeting on Friday at 10 AM; submit documents by Monday.'
            : 'ประชุมโครงการวันศุกร์ เวลา 10 โมง และส่งเอกสารภายในวันจันทร์'
        };
      }
      if (scene.id === 'desk') {
        return {
          text: isEn
            ? 'The laptop screen shows: Meeting at 14:30 · Room 402.'
            : 'หน้าจอโน้ตบุ๊กระบุ: Meeting at 14:30 · Room 402'
        };
      }
      if (scene.id === 'simulator') {
        return {
          text: 'TOP: Meeting Friday at 10 AM'
        };
      }
    }

    if (/งบประมาณ|budget/i.test(qLower)) {
      setActivePipelineStage('vision');
      if (scene.id === 'document') {
        return {
          text: isEn
            ? 'The document states: Event budget 9,000 THB (submit documents by Monday).'
            : 'เอกสารระบุว่า: งบประมาณจัดงาน 9,000 บาท (ส่งเอกสารภายในวันจันทร์)'
        };
      }
      return {
        text: isEn
          ? 'No budget figure appears in this photo. Switch to the “Project meeting notice” scene to test reading the 9,000 THB budget.'
          : 'ไม่พบตัวเลขงบประมาณในภาพนี้ ลองสลับไปที่ฉาก “เอกสารนัดประชุมโครงการ” เพื่อทดสอบอ่านงบประมาณ 9,000 บาท'
      };
    }

    if (/อ่านข้อความ|read text|อ่านทั้งหมด/i.test(qLower)) {
      setActivePipelineStage('vision');
      const formatted = (scene.sources || []).map(s => `[${getSourceTitle(s)}]\n${s.text}`).join('\n\n');
      return { text: formatted || (isEn ? 'No text detected.' : 'ไม่พบข้อความในภาพ') };
    }

    // 4. General Visual Q&A (Qwen3-VL-2B-Instruct)
    setActivePipelineStage('qwen');
    return {
      text: isEn ? scene.summaryEn : scene.summaryTh
    };
  }

  /* ==========================================================================
     9. Executing Voice / Manual Turns & Updating UI
     ========================================================================== */
  function updateCameraStatus() {
    const L = t();
    const voiceStatus = document.getElementById('voiceStatus');
    const depthStatus = document.getElementById('cameraDepthStatus');
    const shutter = document.getElementById('shutter');
    const respPanel = document.getElementById('responsePanel');
    const transBlock = document.getElementById('transcriptBlock');
    const transText = document.getElementById('voiceTranscript');
    const listenRow = document.getElementById('listeningIndicator');
    const ansBlock = document.getElementById('answerBlock');
    const ansText = document.getElementById('inlineAnswer');
    const workRow = document.getElementById('workingIndicator');

    if (voiceStatus) {
      if (isMediaPreview()) voiceStatus.textContent = L.mediaPreview;
      else if (state.isListening) voiceStatus.textContent = recognition ? L.speakNow : L.releaseSample;
      else if (recognition) voiceStatus.textContent = L.transcribing;
      else if (state.isWorking) voiceStatus.textContent = L.analyzing;
      else if (state.isSpeaking) voiceStatus.textContent = L.readingAloud;
      else if (!browserSpeechEnabled()) voiceStatus.textContent = L.holdSample;
      else if (state.reusePhotoOnHold && state.hasCapturedPhoto) voiceStatus.textContent = L.holdReuse;
      else voiceStatus.textContent = L.holdToAsk;
    }

    if (depthStatus) {
      depthStatus.hidden = isMediaPreview();
      depthStatus.textContent = state.depthMode === 'da3' ? L.da3Provenance : L.lidarProvenance;
    }

    if (shutter) {
      shutter.disabled = isMediaPreview();
      shutter.classList.toggle('is-listening', state.isListening);
      shutter.classList.toggle('is-busy', state.isListening || state.isWorking);
    }

    const hasResp = Boolean(state.currentTranscript || state.currentAnswer || state.isListening || state.isWorking || recognition);
    if (respPanel) respPanel.hidden = !hasResp;
    if (transBlock) {
      transBlock.hidden = !state.currentTranscript;
      if (transText) transText.textContent = state.currentTranscript;
    }
    if (listenRow) listenRow.hidden = !(state.isListening && recognition && !state.currentTranscript);
    if (ansBlock) {
      ansBlock.hidden = !state.currentAnswer;
      if (ansText) ansText.textContent = state.currentAnswer;
    }
    if (workRow) workRow.hidden = !state.isWorking;
  }

  function runQuestionTurn(questionText, openConvAfter = false) {
    if (isMediaPreview()) return;
    cancelShutterHold();
    clearTimeout(state.answerTimer);
    stopSpeaking();
    const q = (questionText || '').trim() || (state.appLang === 'en' ? currentScene().defaultPromptEn : currentScene().defaultPromptTh);
    state.currentTranscript = q;
    state.currentAnswer = '';
    state.isListening = false;
    state.isWorking = true;
    setActivePipelineStage('speech');
    updateCameraStatus();

    state.answerTimer = setTimeout(() => {
      state.answerTimer = null;
      const result = evaluateQuestion(q);
      state.isWorking = false;
      state.currentAnswer = result.text;

      // Append to conversation history
      const regionTitle = state.selectedSourceId !== null
        ? getSourceTitle(currentScene().sources[state.selectedSourceId])
        : getRegionLabel(state.region);

      state.messages.push({
        isUser: true,
        text: q,
        regionTitle
      });
      state.messages.push({
        isUser: false,
        action: 'question',
        text: result.text,
        distance: result.distance || null
      });

      renderConversationMessages();
      renderAllCanvases();
      updateCameraStatus();
      setActivePipelineStage('output');

      if (result.centeredCue) {
        playCenteredCue();
      }
      speakAnswer(result.text);

      if (openConvAfter) {
        openSheet('conversation');
      }
    }, 360);
  }

  function executeConversationAction() {
    if (isMediaPreview()) return;
    const L = t();
    const scene = currentScene();
    const input = document.getElementById('questionInput');

    if (state.photoAction === 'question') {
      const q = input?.value.trim() || (state.appLang === 'en' ? scene.defaultPromptEn : scene.defaultPromptTh);
      if (input) input.value = '';
      runQuestionTurn(q, false);
      return;
    }

    // Filter sources by selected source or region
    let sources = scene.sources || [];
    if (state.selectedSourceId !== null && sources[state.selectedSourceId]) {
      sources = [sources[state.selectedSourceId]];
    } else if (state.region.w < 0.95 || state.region.h < 0.95) {
      sources = sources.filter(s => {
        const cx = s.rect.x + s.rect.w / 2;
        const cy = s.rect.y + s.rect.h / 2;
        return cx >= state.region.x && cx <= state.region.x + state.region.w &&
               cy >= state.region.y && cy <= state.region.y + state.region.h;
      });
      if (!sources.length) sources = scene.sources || [];
    }

    const regionTitle = state.selectedSourceId !== null && scene.sources[state.selectedSourceId]
      ? getSourceTitle(scene.sources[state.selectedSourceId])
      : getRegionLabel(state.region);

    if (state.photoAction === 'read') {
      setActivePipelineStage('vision');
      state.messages.push({
        isUser: true,
        text: L.modeRead,
        regionTitle
      });
      const combined = sources.map(s => `[${getSourceTitle(s)}]\n${s.text}`).join('\n\n');
      state.messages.push({
        isUser: false,
        action: 'read',
        text: combined,
        sources
      });
      state.currentTranscript = L.modeRead;
      state.currentAnswer = combined;
      renderConversationMessages();
      updateCameraStatus();
      speakAnswer(combined);
      return;
    }

    if (state.photoAction === 'summarize') {
      setActivePipelineStage('qwen');
      const focusNote = input?.value.trim();
      if (input) input.value = '';
      state.messages.push({
        isUser: true,
        text: focusNote ? `${L.modeSummarize}: ${focusNote}` : L.modeSummarize,
        regionTitle
      });
      const isEn = state.appLang === 'en';
      const summaryText = sources.length === 1
        ? (isEn ? sources[0].summaryEn : sources[0].summaryTh)
        : (isEn ? scene.summaryEn : scene.summaryTh);
      const rawSource = sources.map(s => `[${getSourceTitle(s)}]\n${s.text}`).join('\n\n');
      state.messages.push({
        isUser: false,
        action: 'summarize',
        text: summaryText,
        sourceText: rawSource
      });
      state.currentTranscript = L.modeSummarize;
      state.currentAnswer = summaryText;
      renderConversationMessages();
      updateCameraStatus();
      speakAnswer(summaryText);
    }
  }

  /* ==========================================================================
     10. Conversation Sheet Rendering
     ========================================================================== */
  function renderConversationMessages() {
    const container = document.getElementById('conversationMessages');
    if (!container) return;
    const L = t();
    container.innerHTML = '';

    if (!state.messages.length) {
      const empty = document.createElement('div');
      empty.className = 'conv-empty';
      const h3 = document.createElement('h3');
      h3.textContent = state.photoAction === 'question'
        ? L.emptyAskTitle
        : state.photoAction === 'read' ? L.emptyReadTitle : L.emptySumTitle;
      empty.appendChild(h3);

      if (state.photoAction === 'question') {
        const chip = document.createElement('button');
        chip.type = 'button';
        chip.className = 'conv-suggestion-chip';
        chip.textContent = L.emptyAskChip;
        chip.addEventListener('click', () => runQuestionTurn(L.emptyAskChip, false));
        empty.appendChild(chip);
      } else {
        const p = document.createElement('p');
        p.textContent = state.photoAction === 'read' ? L.emptyReadDesc : L.emptySumDesc;
        empty.appendChild(p);
      }
      container.appendChild(empty);
      return;
    }

    state.messages.forEach(msg => {
      const row = document.createElement('div');
      row.className = `chat-msg ${msg.isUser ? 'is-user' : 'is-assistant'}`;

      if (msg.isUser) {
        if (msg.regionTitle) {
          const meta = document.createElement('span');
          meta.className = 'chat-msg-meta';
          meta.textContent = msg.regionTitle;
          row.appendChild(meta);
        }
        const txt = document.createElement('div');
        txt.className = 'chat-msg-text';
        txt.textContent = msg.text;
        row.appendChild(txt);
      } else {
        const badge = document.createElement('span');
        badge.className = 'app-gold-label';
        badge.textContent = msg.action === 'read'
          ? (state.appLang === 'en' ? 'Text from the photo' : 'ข้อความจากภาพ')
          : 'LunaV';
        row.appendChild(badge);

        if (msg.action === 'read' && Array.isArray(msg.sources) && msg.sources.length) {
          msg.sources.forEach(src => {
            const box = document.createElement('div');
            box.className = 'chat-source-group';
            const title = document.createElement('div');
            title.className = 'chat-source-group-title';
            title.textContent = getSourceTitle(src);
            const body = document.createElement('div');
            body.className = 'chat-source-group-text';
            body.textContent = src.text;
            const sumBtn = document.createElement('button');
            sumBtn.type = 'button';
            sumBtn.className = 'chat-mini-btn';
            sumBtn.textContent = L.summarizeGroup;
            sumBtn.addEventListener('click', () => {
              state.selectedSourceId = src.id;
              state.region = { ...src.rect };
              setPhotoAction('summarize');
              executeConversationAction();
            });
            box.append(title, body, sumBtn);
            row.appendChild(box);
          });
        } else {
          const txt = document.createElement('div');
          txt.className = 'chat-msg-text';
          txt.textContent = msg.text;
          row.appendChild(txt);
        }

        if (msg.sourceText) {
          const det = document.createElement('details');
          det.className = 'settings-disclosure';
          const sum = document.createElement('summary');
          sum.textContent = state.appLang === 'en' ? 'Text used for the summary' : 'ข้อความที่ใช้สรุป';
          const body = document.createElement('div');
          body.className = 'disclosure-body';
          body.textContent = msg.sourceText;
          det.append(sum, body);
          row.appendChild(det);
        }

        const copyBtn = document.createElement('button');
        copyBtn.type = 'button';
        copyBtn.className = 'chat-mini-btn';
        copyBtn.textContent = `⧉ ${L.copyBtn}`;
        copyBtn.addEventListener('click', () => {
          navigator.clipboard?.writeText(msg.text).catch(() => {});
          copyBtn.textContent = `✓ ${L.copiedBtn}`;
          setTimeout(() => { copyBtn.textContent = `⧉ ${L.copyBtn}`; }, 1400);
        });
        row.appendChild(copyBtn);
      }

      container.appendChild(row);
    });

    container.scrollTop = container.scrollHeight;
  }

  /* ==========================================================================
     11. Text Sources Sheet & Distance Selection Sheet Logic
     ========================================================================== */
  function renderSourcesOverlay() {
    const boxesWrap = document.getElementById('sourcesMapBoxes');
    const listWrap = document.getElementById('sourcesListContainer');
    if (!boxesWrap || !listWrap) return;
    boxesWrap.innerHTML = '';
    listWrap.innerHTML = '';
    if (isMediaPreview()) {
      listWrap.textContent = t().mediaPreview;
      return;
    }

    const sources = currentScene().sources || [];
    sources.forEach(src => {
      // Map overlay box
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `source-map-box${state.selectedSourceId === src.id ? ' is-selected' : ''}`;
      btn.style.left = `${src.rect.x * 100}%`;
      btn.style.top = `${src.rect.y * 100}%`;
      btn.style.width = `${src.rect.w * 100}%`;
      btn.style.height = `${src.rect.h * 100}%`;
      const badge = document.createElement('span');
      badge.textContent = String(src.id + 1);
      btn.appendChild(badge);
      btn.addEventListener('click', () => selectTextSource(src));
      boxesWrap.appendChild(btn);

      // List item
      const item = document.createElement('button');
      item.type = 'button';
      item.className = 'source-list-item';
      item.innerHTML = `
        <span class="source-num-badge">${src.id + 1}</span>
        <span class="source-item-copy">
          <strong>${getSourceTitle(src)}</strong>
          <p>${src.text}</p>
        </span>
        <span class="action-chevron">›</span>
      `;
      item.addEventListener('click', () => selectTextSource(src));
      listWrap.appendChild(item);
    });
  }

  function selectTextSource(src) {
    state.selectedSourceId = src.id;
    state.region = { ...src.rect };
    updateRegionLabels();
    renderAllCanvases();
    openSheet('conversation');
    if (state.photoAction === 'question') {
      setPhotoAction('read');
    }
    executeConversationAction();
  }

  function updateDistanceSheetReadout() {
    const L = t();
    const readingEl = document.getElementById('distanceReading');
    const expEl = document.getElementById('distanceExplanation');
    const provEl = document.getElementById('distanceSheetProvenance');
    const navTitle = document.getElementById('distance-nav-title');
    const confirm = document.getElementById('confirmDistance');
    if (confirm) confirm.disabled = isMediaPreview();
    if (isMediaPreview()) {
      if (readingEl) readingEl.textContent = '—';
      if (expEl) expEl.textContent = L.mediaPreview;
      if (provEl) provEl.textContent = '';
      return;
    }
    const sample = sampleDepthAtPoint(state.distancePoint);
    const isDA3 = state.depthMode === 'da3';
    const meters = sample.meters * (isDA3 ? state.da3Scale : 1);
    const decimals = isDA3 ? 1 : 2;
    if (readingEl) {
      readingEl.textContent = `≈ ${meters.toFixed(decimals)} ${L.metersUnit}`;
    }
    if (expEl) {
      expEl.textContent = state.depthMode === 'da3'
        ? (state.appLang === 'en' ? 'Simulated model estimate' : 'ระยะประมาณจากโมเดลจำลอง')
        : (state.appLang === 'en' ? 'Simulated camera depth' : 'ระยะจากกล้องจำลอง');
    }
    if (provEl) {
      provEl.textContent = state.depthMode === 'da3' ? L.da3Provenance : L.lidarProvenance;
    }
    if (navTitle) {
      navTitle.textContent = state.depthMode === 'da3' ? L.distTitleDa3 : L.distTitleLidar;
    }
  }

  function updateObstacleStatus() {
    const L = t();
    const liveEl = document.getElementById('obstacleLiveStatus');
    const setEl = document.getElementById('obstacleStatus');
    const scene = currentScene();
    const hasCloseObstacle = scene.hasObstacle && scene.obstacleDistance <= state.obstacleWarnDist;

    if (isMediaPreview()) {
      if (liveEl) liveEl.hidden = true;
      if (setEl) setEl.textContent = L.mediaPreview;
      return;
    }
    if (!state.obstacleEnabled) {
      if (liveEl) liveEl.hidden = true;
      if (setEl) setEl.textContent = L.obsOff;
      return;
    }

    const msg = hasCloseObstacle ? L.obsWarning : L.obsClear;
    if (liveEl) {
      liveEl.hidden = false;
      liveEl.textContent = msg;
    }
    if (setEl) setEl.textContent = msg;
  }

  /* ==========================================================================
     12. Sheet Navigation & Mode Switching
     ========================================================================== */
  const SHEET_MAP = {
    settings: 'sheet-settings',
    conversation: 'sheet-conversation',
    region: 'sheet-region',
    sources: 'sheet-sources',
    distance: 'sheet-distance',
    performance: 'sheet-performance',
    about: 'sheet-about'
  };

  let sheetTrigger;
  function openSheet(name) {
    const previous = state.activeSheet;
    const movingFromSheet = document.activeElement?.closest('.app-sheet');
    if (previous === 'camera' && name !== 'camera') sheetTrigger = document.activeElement;
    state.activeSheet = name;
    document.getElementById('screen-camera').inert = name !== 'camera';
    Object.entries(SHEET_MAP).forEach(([key, id]) => {
      const el = document.getElementById(id);
      if (el) el.hidden = key !== name;
    });
    document.querySelectorAll('[data-open-screen]').forEach(btn => {
      btn.classList.toggle('is-active', btn.dataset.openScreen === name);
    });
    if (name !== 'camera') document.getElementById(SHEET_MAP[name])?.focus({ preventScroll: true });
    else if (movingFromSheet) (sheetTrigger || document.getElementById('cameraSettings'))?.focus({ preventScroll: true });
    renderAllCanvases();
  }

  document.getElementById('lunav-app').addEventListener('keydown', event => {
    if (event.key === 'Escape' && state.activeSheet !== 'camera') openSheet('camera');
  });

  function setPhotoAction(action) {
    state.photoAction = action;
    const L = t();
    document.querySelectorAll('[data-photo-action]').forEach(btn => {
      btn.classList.toggle('is-active', btn.dataset.photoAction === action);
    });
    const distBar = document.getElementById('convDistanceBar');
    const srcBar = document.getElementById('convSourcesBar');
    const input = document.getElementById('questionInput');
    const sendBtn = document.getElementById('sendQuestion');
    const note = document.getElementById('convComposerNote');
    const srcLabel = document.getElementById('discoverSourcesLabel');

    if (distBar) distBar.hidden = action !== 'question';
    if (srcBar) srcBar.hidden = action === 'question';
    if (srcLabel) {
      const count = (currentScene().sources || []).length;
      srcLabel.textContent = count ? L.chooseFromGroups(count) : L.discoverSources;
    }
    if (input) {
      input.hidden = action === 'read';
      input.placeholder = action === 'question' ? L.placeholderAsk : L.placeholderSum;
    }
    if (sendBtn) {
      sendBtn.disabled = isMediaPreview();
      sendBtn.textContent = action === 'question' ? '↑' : action === 'read' ? L.modeRead : L.modeSummarize;
    }
    if (note) {
      note.textContent = isMediaPreview() ? L.mediaPreview : action === 'question' ? L.processedOnDevice : L.checkTextNote;
    }
    renderConversationMessages();
  }

  function updateRegionLabels() {
    const L = t();
    const scene = currentScene();
    const titleEl = document.getElementById('conv-region-title');
    const selEl = document.getElementById('selectedRegionLabel');
    const label = state.selectedSourceId !== null && scene.sources[state.selectedSourceId]
      ? getSourceTitle(scene.sources[state.selectedSourceId])
      : getRegionLabel(state.region);
    if (titleEl) titleEl.textContent = label;
    if (selEl) selEl.textContent = `${L.selectedPrefix}${getRegionLabel(state.region)}`;
  }

  /* ==========================================================================
     13. App Interface Language Sync (TH / EN)
     ========================================================================== */
  function applyAppLanguage(lang) {
    state.appLang = lang === 'en' ? 'en' : 'th';
    const L = t();
    const appRoot = document.getElementById('lunav-app');
    if (appRoot) appRoot.dataset.appLang = state.appLang;

    document.querySelectorAll('[data-set-app-lang]').forEach(btn => {
      btn.classList.toggle('is-active', btn.dataset.setAppLang === state.appLang);
    });

    const setTxt = (id, val) => {
      const el = document.getElementById(id);
      if (el) el.textContent = val;
    };

    setTxt('label-you-asked', L.youAsked);
    setTxt('label-listening', L.listening);
    setTxt('btn-open-conv-inline', L.openConv);
    setTxt('settings-nav-title', L.settingsTitle);
    setTxt('closeSettings', L.done);
    setTxt('st-brand-sub', L.brandSub);
    setTxt('st-lang-heading', L.appLangHeading);
    setTxt('st-lang-note', L.appLangNote);
    setTxt('st-speech-heading', L.speechHeading);
    setTxt('st-speech-sub', L.speechSub);
    setTxt('st-speech-status', L.speechStatus);
    setTxt('st-reuse-label', L.reuseLabel);
    setTxt('st-reuse-note', L.reuseNote);
    setTxt('st-hold-note', L.holdNote);
    setTxt('st-prep-speech-btn', L.prepSpeechBtn);
    setTxt('st-speech-about-sum', L.aboutSpeechSum);
    setTxt('st-tts-heading', L.ttsHeading);
    setTxt('st-tts-sub', L.ttsSub);
    setTxt('st-tts-toggle-lbl', L.ttsToggle);
    setTxt('st-voice-th-lbl', L.voiceThLbl);
    setTxt('st-voice-en-lbl', L.voiceEnLbl);
    setTxt('st-preview-tts-btn', L.previewTts);
    setTxt('st-stop-tts-btn', L.stopTts);
    setTxt('st-tts-status', L.ttsReady);
    setTxt('st-obs-heading', L.obsHeading);
    setTxt('st-obs-toggle-lbl', L.obsToggle);
    setTxt('st-obs-start-lbl', L.obsStartLbl);
    setTxt('st-obs-close-lbl', L.obsCloseLbl);
    setTxt('st-obs-int-lbl', L.obsIntLbl);
    setTxt('st-obs-test-btn', L.obsTestBtn);
    setTxt('st-tools-heading', L.toolsHeading);
    setTxt('st-tools-sub', L.toolsSub);
    setTxt('st-tool-sample', L.toolSample);
    setTxt('st-tool-import', L.toolImport);
    setTxt('st-tool-ask', L.toolAsk);
    setTxt('st-tool-read', L.toolRead);
    setTxt('st-tool-sum', L.toolSum);
    setTxt('st-tool-lidar', L.toolLidar);
    setTxt('st-sys-heading', L.sysHeading);
    setTxt('st-sys-ready', L.sysReady);
    setTxt('st-sys-depth-lbl', L.sysDepthLbl);
    setTxt('st-clear-ctx-btn', L.clearCtxBtn);
    setTxt('st-perf-btn', L.perfBtn);
    setTxt('st-privacy-note', L.privacyNote);
    setTxt('st-about-heading', L.aboutHeading);
    setTxt('st-open-about-btn', L.openAboutBtn);
    setTxt('conv-sheet-title', L.convTitle);
    setTxt('modelStatus', L.convReady);
    setTxt('mode_question', L.modeQuestion);
    setTxt('mode_read', L.modeRead);
    setTxt('mode_summarize', L.modeSummarize);
    setTxt('conv-region-sub', L.tapToSelectRegion);
    setTxt('conv-dist-hint', L.askDistHint);
    setTxt('measureLiDAR', L.choosePoint);
    setTxt('cancelRegion', L.cancel);
    setTxt('region-nav-title', L.regionTitle);
    setTxt('confirmRegion', L.useThisRegion);
    setTxt('reg-guide-title', L.dragRegionGuide);
    setTxt('reg-guide-sub', L.dragRegionSub);
    setTxt('regionFull', L.wholePhoto);
    setTxt('regionTop', L.top);
    setTxt('regionMiddle', L.middle);
    setTxt('regionBottom', L.bottom);
    setTxt('sources-nav-title', L.sourcesTitle);
    setTxt('closeTextSources', L.done);
    setTxt('src-sheet-lead', L.sourcesLead);
    setTxt('cancelDistance', L.cancel);
    setTxt('confirmDistance', L.useThisPoint);
    setTxt('dist-sheet-heading', L.tapObjectDist);
    setTxt('distanceCenter', L.chooseCenter);
    setTxt('closePerformance', L.done);
    setTxt('ab-back-lbl', L.back);

    updateRegionLabels();
    setPhotoAction(state.photoAction);
    updateCameraStatus();
    renderAllCanvases();
    updateMediaControls();
  }

  /* ==========================================================================
     14. Launch Intro Sequence (LunaIntroView.swift)
     ========================================================================== */
  let introTimerIds = [];
  function playAppIntro() {
    introTimerIds.forEach(clearTimeout);
    introTimerIds = [];
    const overlay = document.getElementById('app-intro');
    const retired = document.getElementById('app-intro-retired');
    const lockup = document.getElementById('app-intro-lockup');
    if (!overlay || !retired || !lockup) return;

    overlay.hidden = false;
    overlay.style.opacity = '1';
    retired.classList.remove('is-striking', 'is-collapsed');
    lockup.classList.remove('is-docking');

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      retired.classList.add('is-collapsed');
      introTimerIds.push(setTimeout(() => { overlay.hidden = true; }, 260));
      return;
    }

    introTimerIds.push(setTimeout(() => {
      retired.classList.add('is-striking');
    }, 380));

    introTimerIds.push(setTimeout(() => {
      retired.classList.add('is-collapsed');
    }, 1150));

    introTimerIds.push(setTimeout(() => {
      lockup.classList.add('is-docking');
      overlay.style.opacity = '0';
    }, 1750));

    introTimerIds.push(setTimeout(() => {
      overlay.hidden = true;
    }, 2150));
  }

  /* ==========================================================================
     15. Interactive Event Listeners (Shutter, Drag Region, Tap Distance, Webcam)
     ========================================================================== */
  // Shutter hold (>= 250ms) vs short tap (< 250ms)
  const shutterBtn = document.getElementById('shutter');
  let recognition = null;
  let recognitionFinishTimer = null;

  function cancelShutterHold() {
    clearTimeout(state.pressTimer);
    clearTimeout(recognitionFinishTimer);
    state.pressStartTime = 0;
    state.isListening = false;
    shutterBtn?.classList.remove('is-pressing');
    document.getElementById('dynamic-island')?.classList.remove('is-active', 'is-mic');
    const active = recognition;
    recognition = null;
    try { active?.abort(); } catch { /* already stopped */ }
  }

  function beginShutterHold(e) {
    if (isMediaPreview() || state.pressStartTime || recognition || (e && e.button !== 0)) return;
    if (state.isWorking) {
      clearTimeout(state.answerTimer);
      state.answerTimer = null;
      state.isWorking = false;
      updateCameraStatus();
      return;
    }
    stopSpeaking();
    if (e) shutterBtn?.setPointerCapture(e.pointerId);
    state.pressStartTime = performance.now();
    shutterBtn?.classList.add('is-pressing');

    state.pressTimer = setTimeout(() => {
      state.isListening = true;
      state.currentTranscript = '';
      state.currentAnswer = '';
      setActivePipelineStage('capture');

      // Microphone access is opt-in. The default path uses a sample question.
      const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (browserSpeechEnabled()) {
        try {
          const session = new SpeechRec();
          recognition = session;
          session.lang = state.speechLang === 'en' ? 'en-US' : 'th-TH';
          session.interimResults = true;
          session.onresult = ev => {
            if (recognition !== session) return;
            const text = Array.from(ev.results).map(r => r[0].transcript).join('');
            if (text) {
              state.currentTranscript = text;
              updateCameraStatus();
            }
          };
          session.onend = () => {
            if (recognition !== session) return;
            recognition = null;
            document.getElementById('dynamic-island')?.classList.remove('is-active', 'is-mic');
            updateCameraStatus();
          };
          session.start();
          document.getElementById('dynamic-island')?.classList.add('is-active', 'is-mic');
        } catch { recognition = null; }
      }
      updateCameraStatus();
    }, 240);
  }

  function endShutterHold() {
    if (!state.pressStartTime) return;
    const heldMs = performance.now() - state.pressStartTime;
    state.pressStartTime = 0;
    clearTimeout(state.pressTimer);
    shutterBtn?.classList.remove('is-pressing');
    document.getElementById('dynamic-island')?.classList.remove('is-active', 'is-mic');

    if (heldMs < 240 && !state.isListening) {
      // Short tap: capture only
      state.hasCapturedPhoto = true;
      state.isListening = false;
      const voiceStatus = document.getElementById('voiceStatus');
      if (voiceStatus) voiceStatus.textContent = t().photoTaken;
      setActivePipelineStage('capture');
      renderAllCanvases();
      return;
    }

    state.isListening = false;
    const send = () => {
      const fallbackPrompt = state.appLang === 'en' ? currentScene().defaultPromptEn : currentScene().defaultPromptTh;
      runQuestionTurn(state.currentTranscript.trim() || fallbackPrompt, false);
    };
    const active = recognition;
    if (!active) {
      send();
      return;
    }
    const finish = () => {
      if (recognition === active) send();
    };
    active.onend = finish;
    recognitionFinishTimer = setTimeout(finish, 700);
    try { active.stop(); } catch { finish(); }
    updateCameraStatus();
  }

  if (shutterBtn) {
    shutterBtn.addEventListener('pointerdown', beginShutterHold);
    shutterBtn.addEventListener('pointerup', endShutterHold);
    shutterBtn.addEventListener('pointercancel', () => { cancelShutterHold(); updateCameraStatus(); });
    shutterBtn.addEventListener('click', e => {
      if (e.detail !== 0) return;
      beginShutterHold();
      endShutterHold();
    });
  }

  // Space holds the focused shutter or starts from the page itself.
  window.addEventListener('keydown', e => {
    if (e.code !== 'Space' || state.activeSheet !== 'camera' || isMediaPreview() ||
        ![document.body, shutterBtn].includes(document.activeElement)) return;
    e.preventDefault();
    if (!e.repeat) beginShutterHold();
  });
  window.addEventListener('keyup', e => {
    if (e.code === 'Space' && state.pressStartTime) {
      e.preventDefault();
      endShutterHold();
    }
  });
  document.getElementById('demo-voice-input')?.addEventListener('change', e => {
    if (!e.target.checked) cancelShutterHold();
    updateCameraStatus();
  });

  // Top bar & Sheet buttons
  document.getElementById('cameraSettings')?.addEventListener('click', () => openSheet('settings'));
  document.getElementById('closeSettings')?.addEventListener('click', () => openSheet('camera'));
  document.getElementById('btn-open-conv-inline')?.addEventListener('click', () => openSheet('conversation'));
  document.getElementById('retake')?.addEventListener('click', () => openSheet('camera'));
  document.getElementById('conv-perf-btn')?.addEventListener('click', () => openSheet('performance'));
  document.getElementById('cameraPerformance')?.addEventListener('click', () => openSheet('performance'));
  document.getElementById('closePerformance')?.addEventListener('click', () => openSheet('camera'));
  document.getElementById('openAbout')?.addEventListener('click', () => openSheet('about'));
  document.getElementById('closeAbout')?.addEventListener('click', () => openSheet('settings'));
  document.getElementById('chooseRegion')?.addEventListener('click', () => openSheet('region'));
  document.getElementById('cancelRegion')?.addEventListener('click', () => openSheet('conversation'));
  document.getElementById('confirmRegion')?.addEventListener('click', () => {
    state.selectedSourceId = null;
    updateRegionLabels();
    openSheet('conversation');
  });
  document.getElementById('discoverTextSources')?.addEventListener('click', () => openSheet('sources'));
  document.getElementById('closeTextSources')?.addEventListener('click', () => openSheet('conversation'));
  document.getElementById('measureLiDAR')?.addEventListener('click', () => openSheet('distance'));
  document.getElementById('cancelDistance')?.addEventListener('click', () => openSheet('conversation'));
  document.getElementById('confirmDistance')?.addEventListener('click', () => {
    if (isMediaPreview()) return;
    const sample = sampleDepthAtPoint(state.distancePoint);
    const subjTh = sample.target ? sample.target.nameTh : 'จุดที่เลือก';
    const subjEn = sample.target ? sample.target.nameEn : 'Selected point';
    const ans = formatDistanceAnswer(subjTh, subjEn, sample.meters, false);
    state.messages.push({
      isUser: true,
      text: state.appLang === 'en' ? 'Distance at selected point' : 'วัดระยะจุดที่เลือก',
      regionTitle: state.appLang === 'en' ? 'Selected point' : 'ตำแหน่งที่วัด'
    });
    state.messages.push({
      isUser: false,
      action: 'question',
      text: ans
    });
    state.currentAnswer = ans;
    renderConversationMessages();
    updateCameraStatus();
    openSheet('conversation');
    speakAnswer(ans);
  });

  // Clear context buttons
  const clearAllContext = () => {
    cancelShutterHold();
    clearTimeout(state.answerTimer);
    state.answerTimer = null;
    state.isWorking = false;
    state.messages = [];
    state.currentTranscript = '';
    state.currentAnswer = '';
    state.selectedSourceId = null;
    state.region = { x: 0, y: 0, w: 1, h: 1 };
    stopSpeaking();
    updateRegionLabels();
    renderConversationMessages();
    updateCameraStatus();
  };
  document.getElementById('clearContext')?.addEventListener('click', clearAllContext);
  document.getElementById('settingsClearContext')?.addEventListener('click', () => {
    clearAllContext();
    openSheet('camera');
  });

  // Settings Manual Testing Tools
  document.getElementById('samplePhoto')?.addEventListener('click', () => {
    selectScene('simulator');
    openSheet('conversation');
  });
  document.getElementById('importPhoto')?.addEventListener('click', () => {
    document.getElementById('demo-file-input')?.click();
  });
  document.getElementById('manualConversation')?.addEventListener('click', () => {
    setPhotoAction('question');
    openSheet('conversation');
  });
  document.getElementById('manualRead')?.addEventListener('click', () => {
    setPhotoAction('read');
    openSheet('conversation');
  });
  document.getElementById('manualSummary')?.addEventListener('click', () => {
    setPhotoAction('summarize');
    openSheet('conversation');
  });
  document.getElementById('manualLiDAR')?.addEventListener('click', () => {
    openSheet('distance');
  });

  // Mode segmented buttons in ConversationSheet
  document.querySelectorAll('[data-photo-action]').forEach(btn => {
    btn.addEventListener('click', () => setPhotoAction(btn.dataset.photoAction));
  });

  // Send question in ConversationSheet
  document.getElementById('sendQuestion')?.addEventListener('click', executeConversationAction);
  document.getElementById('questionInput')?.addEventListener('keydown', e => {
    if (e.key === 'Enter') {
      e.preventDefault();
      executeConversationAction();
    }
  });

  // Region selection presets & drag on #regionCanvas
  const REGION_PRESETS = {
    full: { x: 0, y: 0, w: 1, h: 1 },
    top: { x: 0, y: 0, w: 1, h: 0.5 },
    middle: { x: 0, y: 0.25, w: 1, h: 0.5 },
    bottom: { x: 0, y: 0.5, w: 1, h: 0.5 }
  };
  document.querySelectorAll('[data-region-preset]').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('[data-region-preset]').forEach(b => b.classList.remove('is-selected'));
      btn.classList.add('is-selected');
      state.region = { ...REGION_PRESETS[btn.dataset.regionPreset] };
      state.selectedSourceId = null;
      updateRegionLabels();
      renderAllCanvases();
    });
  });

  const regCanvas = document.getElementById('regionCanvas');
  if (regCanvas) {
    let dragStart = null;
    const normPt = e => {
      const rect = regCanvas.getBoundingClientRect();
      const clientX = e.touches ? e.touches[0].clientX : e.clientX;
      const clientY = e.touches ? e.touches[0].clientY : e.clientY;
      return {
        x: Math.min(1, Math.max(0, (clientX - rect.left) / rect.width)),
        y: Math.min(1, Math.max(0, (clientY - rect.top) / rect.height))
      };
    };
    regCanvas.addEventListener('pointerdown', e => {
      dragStart = normPt(e);
      regCanvas.setPointerCapture(e.pointerId);
    });
    regCanvas.addEventListener('pointermove', e => {
      if (!dragStart) return;
      const cur = normPt(e);
      const w = Math.abs(cur.x - dragStart.x);
      const h = Math.abs(cur.y - dragStart.y);
      if (w > 0.06 && h > 0.06) {
        state.region = {
          x: Math.min(dragStart.x, cur.x),
          y: Math.min(dragStart.y, cur.y),
          w,
          h
        };
        document.querySelectorAll('[data-region-preset]').forEach(b => b.classList.remove('is-selected'));
        updateRegionLabels();
        drawSceneToCanvas(regCanvas, { regionOverlay: state.region });
      }
    });
    regCanvas.addEventListener('pointerup', () => { dragStart = null; });
  }

  // Distance selection canvas tap
  const distCanvas = document.getElementById('distanceCanvas');
  if (distCanvas) {
    distCanvas.addEventListener('click', e => {
      const rect = distCanvas.getBoundingClientRect();
      state.distancePoint = {
        x: Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)),
        y: Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height))
      };
      renderAllCanvases();
    });
  }
  document.getElementById('distanceCenter')?.addEventListener('click', () => {
    state.distancePoint = { x: 0.5, y: 0.5 };
    renderAllCanvases();
  });

  // Settings controls (Language, Speech, TTS, Obstacle Haptics, DA3 Calibration)
  document.querySelectorAll('[data-set-app-lang]').forEach(btn => {
    btn.addEventListener('click', () => applyAppLanguage(btn.dataset.setAppLang));
  });
  document.querySelectorAll('[data-set-speech-lang]').forEach(btn => {
    btn.addEventListener('click', () => {
      state.speechLang = btn.dataset.setSpeechLang;
      document.querySelectorAll('[data-set-speech-lang]').forEach(b => {
        b.classList.toggle('is-active', b.dataset.setSpeechLang === state.speechLang);
      });
    });
  });
  document.getElementById('reusePhotoOnHold')?.addEventListener('change', e => {
    state.reusePhotoOnHold = e.target.checked;
    updateCameraStatus();
  });
  document.getElementById('answerSpeechEnabled')?.addEventListener('change', e => {
    state.ttsEnabled = e.target.checked;
    if (!state.ttsEnabled) stopSpeaking();
  });
  document.getElementById('previewAnswerSpeech')?.addEventListener('click', () => {
    const sample = state.speechLang === 'en'
      ? 'The water bottle is about one meter away from the camera.'
      : 'ขวดน้ำอยู่ห่างจากกล้องประมาณหนึ่งเมตร';
    speakAnswer(sample);
  });
  document.getElementById('stopAnswerSpeech')?.addEventListener('click', stopSpeaking);

  document.getElementById('obstacleWarnings')?.addEventListener('change', e => {
    state.obstacleEnabled = e.target.checked;
    updateObstacleStatus();
    if (state.obstacleEnabled) triggerHapticBuzz();
  });
  document.getElementById('obstacleWarningDistance')?.addEventListener('input', e => {
    state.obstacleWarnDist = parseFloat(e.target.value);
    const lbl = document.getElementById('obs-start-val');
    if (lbl) lbl.textContent = `${state.obstacleWarnDist.toFixed(1)} ${t().metersUnit}`;
    updateObstacleStatus();
  });
  document.getElementById('obstacleCloseDistance')?.addEventListener('input', e => {
    state.obstacleCloseDist = parseFloat(e.target.value);
    const lbl = document.getElementById('obs-close-val');
    if (lbl) lbl.textContent = `${state.obstacleCloseDist.toFixed(1)} ${t().metersUnit}`;
  });
  document.getElementById('obstacleIntensity')?.addEventListener('input', e => {
    state.obstacleMaxIntensity = parseFloat(e.target.value);
    const lbl = document.getElementById('obs-int-val');
    if (lbl) lbl.textContent = `${Math.round(state.obstacleMaxIntensity * 100)}%`;
  });
  document.getElementById('obstacleHapticsTest')?.addEventListener('click', playCenteredCue);

  document.getElementById('calibrateMonocularDepth')?.addEventListener('click', () => {
    if (isMediaPreview()) return;
    const known = parseFloat(document.getElementById('knownDepthDistance')?.value || '1.0');
    if (known >= 0.3 && known <= 8.0) {
      const centerRaw = sampleDepthAtPoint({ x: 0.5, y: 0.5 }).meters;
      state.da3Scale = Math.min(4.0, Math.max(0.25, known / centerRaw));
      const scaleEl = document.getElementById('da3-scale-val');
      if (scaleEl) scaleEl.textContent = state.da3Scale.toFixed(3);
      renderAllCanvases();
    }
  });
  document.getElementById('resetDepthCalibration')?.addEventListener('click', () => {
    state.da3Scale = 1.0;
    const scaleEl = document.getElementById('da3-scale-val');
    if (scaleEl) scaleEl.textContent = '1.000';
    renderAllCanvases();
  });

  /* ==========================================================================
     16. Right Companion Panel Controls (Scene Cards, Sensor Mode, Voice Chips, Jumpers)
     ========================================================================== */
  function updateMediaControls() {
    const L = t();
    const preview = isMediaPreview();
    const btn = document.getElementById('btn-toggle-webcam');
    const label = btn?.querySelector('[data-camera-label]') || btn?.querySelector('span');
    const status = document.getElementById('demo-media-status');
    if (label) label.textContent = state.webcamStream ? L.stopCameraPreview : L.previewCamera;
    btn?.classList.toggle('is-active', Boolean(state.webcamStream));
    btn?.setAttribute('aria-pressed', String(Boolean(state.webcamStream)));
    if (status) {
      status.hidden = !state.cameraError && !preview;
      status.textContent = state.cameraError ? L.cameraUnavailable : preview ? L.mediaPreview : '';
    }
    document.querySelectorAll('[data-scene]').forEach(card => {
      const active = !preview && card.dataset.scene === state.sceneId;
      card.classList.toggle('is-active', active);
      card.setAttribute('aria-pressed', String(active));
    });
    const calibrate = document.getElementById('calibrateMonocularDepth');
    if (calibrate) calibrate.disabled = preview;
  }

  function stopCameraPreview() {
    state.webcamStream?.getTracks().forEach(track => track.stop());
    state.webcamStream = null;
    const video = document.getElementById('app-webcam-video');
    if (video) {
      video.srcObject = null;
      video.hidden = true;
    }
  }

  function scrollToPhoneOnMobile() {
    if (!window.matchMedia('(max-width: 760px)').matches) return;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    document.getElementById('iphone-frame')?.scrollIntoView({ block: 'start', behavior: reduced ? 'instant' : 'smooth' });
  }

  function selectScene(sceneId) {
    mediaRequest++;
    const shouldClear = sceneId !== state.sceneId || isMediaPreview();
    stopCameraPreview();
    state.sceneId = sceneId;
    state.customImage = null;
    state.cameraError = false;
    state.selectedSourceId = null;
    state.region = { x: 0, y: 0, w: 1, h: 1 };
    if (shouldClear) clearAllContext();
    if (sceneId === 'walkway') {
      state.obstacleEnabled = true;
      const obsToggle = document.getElementById('obstacleWarnings');
      if (obsToggle) obsToggle.checked = true;
    }
    updateMediaControls();
    updateRegionLabels();
    setPhotoAction(state.photoAction);
    renderAllCanvases();
    updateCameraStatus();
  }

  document.querySelectorAll('[data-scene]').forEach(card => {
    card.addEventListener('click', () => selectScene(card.dataset.scene));
  });

  document.querySelectorAll('[data-depth-mode]').forEach(pill => {
    pill.addEventListener('click', () => {
      state.depthMode = pill.dataset.depthMode;
      document.querySelectorAll('[data-depth-mode]').forEach(p => {
        const active = p.dataset.depthMode === state.depthMode;
        p.classList.toggle('is-active', active);
        p.setAttribute('aria-pressed', String(active));
      });
      const sysDepthVal = document.getElementById('st-sys-depth-val');
      const pfSrcVal = document.getElementById('pf-src-val');
      if (sysDepthVal) sysDepthVal.textContent = state.depthMode === 'da3' ? 'Depth Anything 3 Metric' : 'LiDAR';
      if (pfSrcVal) pfSrcVal.textContent = state.depthMode === 'da3' ? 'Depth Anything 3 Metric' : 'LiDAR';
      updateCameraStatus();
      renderAllCanvases();
    });
  });

  document.querySelectorAll('[data-voice-prompt]').forEach(chip => {
    chip.addEventListener('click', () => {
      const prompt = state.appLang === 'en' && chip.dataset.voicePromptEn
        ? chip.dataset.voicePromptEn
        : chip.dataset.voicePrompt;

      // Route sample questions to the matching fixture and leave preview mode.
      let scene = state.sceneId;
      if (/กุญแจ|keys/i.test(prompt)) scene = 'desk';
      else if (/งบประมาณ|budget/i.test(prompt)) scene = 'document';
      else if (/น้ำส้ม|orange|เมนู|menu|เวลาเปิด|opening|ราคา|price|ขวด|bottles?/i.test(prompt)) scene = 'cafe';
      selectScene(scene);

      openSheet('camera');
      runQuestionTurn(prompt, false);
      scrollToPhoneOnMobile();
    });
  });

  document.querySelectorAll('[data-open-screen]').forEach(btn => {
    btn.addEventListener('click', () => {
      openSheet(btn.dataset.openScreen);
      scrollToPhoneOnMobile();
    });
  });

  // Top Stage Toolbar (Replay Intro, Upload Photo, Live Webcam)
  document.getElementById('btn-replay-app-intro')?.addEventListener('click', () => {
    openSheet('camera');
    playAppIntro();
  });

  document.getElementById('btn-upload-photo')?.addEventListener('click', () => {
    document.getElementById('demo-file-input')?.click();
  });

  document.getElementById('demo-file-input')?.addEventListener('change', e => {
    const file = e.target.files?.[0];
    if (!file) return;
    e.target.value = '';
    const request = ++mediaRequest;
    const reader = new FileReader();
    reader.onload = ev => {
      const img = new Image();
      img.onload = () => {
        if (request !== mediaRequest) return;
        stopCameraPreview();
        state.customImage = img;
        state.cameraError = false;
        clearAllContext();
        setPhotoAction(state.photoAction);
        updateMediaControls();
        openSheet('camera');
      };
      img.src = ev.target.result;
    };
    reader.readAsDataURL(file);
  });

  document.getElementById('btn-toggle-webcam')?.addEventListener('click', async () => {
    const video = document.getElementById('app-webcam-video');
    if (!video) return;

    if (state.webcamStream) {
      selectScene(state.sceneId);
      return;
    }

    const request = ++mediaRequest;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
      if (request !== mediaRequest) {
        stream.getTracks().forEach(track => track.stop());
        return;
      }
      state.customImage = null;
      state.cameraError = false;
      state.webcamStream = stream;
      video.srcObject = stream;
      video.hidden = false;
      clearAllContext();
      setPhotoAction(state.photoAction);
      updateMediaControls();
      openSheet('camera');
    } catch {
      if (request === mediaRequest) {
        state.cameraError = true;
        updateMediaControls();
      }
    }
  });
  window.addEventListener('pagehide', () => {
    mediaRequest++;
    stopCameraPreview();
    cancelShutterHold();
    clearTimeout(state.answerTimer);
    state.isWorking = false;
    setPhotoAction(state.photoAction);
    updateMediaControls();
    stopSpeaking();
    renderAllCanvases();
  });

  // Sync with website header language toggle (lunav:languagechange event from docs-language.js)
  window.addEventListener('lunav:languagechange', e => {
    const nextLang = e.detail?.language || document.documentElement.lang;
    applyAppLanguage(nextLang);
  });

  // Initial render
  applyAppLanguage(document.documentElement.lang);
  renderAllCanvases();
  renderConversationMessages();
  setTimeout(playAppIntro, 220);
})();
