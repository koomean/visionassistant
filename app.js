// Vision Assistant JS Scripts - Bilingual Support & Premium UX Interactivity

document.addEventListener('DOMContentLoaded', () => {
    // Initialize Lucide Icons
    if (typeof lucide !== 'undefined') {
        lucide.createIcons();
    }

    // --- Language Detection & Switching System ---
    const getInitialLanguage = () => {
        const savedLang = localStorage.getItem('vision-assistant-lang');
        if (savedLang) return savedLang;
        
        // Auto-detect browser/system locale
        const userLocales = navigator.languages || [navigator.language || navigator.userLanguage];
        for (const locale of userLocales) {
            if (locale.toLowerCase().startsWith('th')) {
                return 'th';
            }
        }
        return 'en';
    };

    const setLanguage = (lang) => {
        const body = document.body;
        // Fade out transition
        body.style.opacity = '0';
        
        setTimeout(() => {
            document.documentElement.setAttribute('data-lang', lang);
            document.documentElement.lang = lang;
            localStorage.setItem('vision-assistant-lang', lang);
            
            // Sync navigation buttons
            document.querySelectorAll('.lang-toggle-btn').forEach(btn => {
                if (btn.getAttribute('data-value') === lang) {
                    btn.classList.add('active');
                } else {
                    btn.classList.remove('active');
                }
            });
            
            // Adjust title metadata based on lang
            if (lang === 'th') {
                document.title = 'Vision Assistant | ผู้ช่วยด้านภาพออฟไลน์ 100% บน iPhone';
            } else {
                document.title = 'Vision Assistant | On-Device AI Visual Assistant for iPhone';
            }
            
            // Fade back in
            body.style.opacity = '1';
        }, 220);
    };

    // Attach click listeners to language selector
    document.querySelectorAll('.lang-toggle-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const selectedLang = btn.getAttribute('data-value');
            if (selectedLang !== document.documentElement.getAttribute('data-lang')) {
                setLanguage(selectedLang);
            }
        });
    });

    // Run language initialization immediately
    const initialLang = getInitialLanguage();
    // Do not transition on first load for better performance
    document.documentElement.setAttribute('data-lang', initialLang);
    document.documentElement.lang = initialLang;
    document.querySelectorAll('.lang-toggle-btn').forEach(btn => {
        if (btn.getAttribute('data-value') === initialLang) {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });

    // --- Header Scrolled Background Transition ---
    const header = document.querySelector('.header');
    window.addEventListener('scroll', () => {
        if (window.scrollY > 20) {
            header.classList.add('scrolled');
        } else {
            header.classList.remove('scrolled');
        }
    });

    // --- Scroll-Triggered Reveal Animations ---
    const revealElements = document.querySelectorAll('.reveal');
    const revealObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('active');
                observer.unobserve(entry.target);
            }
        });
    }, {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    });

    revealElements.forEach(el => revealObserver.observe(el));

    // --- Interactive Pipeline / Flowchart ---
    const pipelineNodes = document.querySelectorAll('.pipeline-node');
    const pipelineDetails = document.querySelectorAll('.detail-card');
    const connectors = document.querySelectorAll('.pipeline-connector');

    pipelineNodes.forEach((node, index) => {
        node.addEventListener('click', () => {
            // Update active node styling
            pipelineNodes.forEach(n => n.classList.remove('active'));
            node.classList.add('active');

            // Update connectors
            connectors.forEach((conn, connIndex) => {
                if (connIndex < index) {
                    conn.classList.add('active');
                } else {
                    conn.classList.remove('active');
                }
            });

            // Toggle detail card with transition
            const targetId = node.getAttribute('data-target');
            pipelineDetails.forEach(card => {
                card.classList.remove('active');
                if (card.id === targetId) {
                    card.classList.add('active');
                }
            });
        });
    });

    // --- Setup Guide Navigation Tabs ---
    const tabButtons = document.querySelectorAll('.setup-tab-btn');
    const tabPanes = document.querySelectorAll('.tab-pane');

    tabButtons.forEach(btn => {
        btn.addEventListener('click', () => {
            // Update buttons active class
            tabButtons.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            // Update content pane active class
            const targetId = btn.getAttribute('data-target');
            tabPanes.forEach(pane => {
                if (pane.id === targetId) {
                    pane.classList.add('active');
                } else {
                    pane.classList.remove('active');
                }
            });
        });
    });

    // --- Code Copy to Clipboard System ---
    const copyButtons = document.querySelectorAll('.copy-btn');
    
    copyButtons.forEach(btn => {
        btn.addEventListener('click', async () => {
            const targetSelector = btn.getAttribute('data-clipboard-target');
            const codeEl = document.querySelector(targetSelector);
            if (!codeEl) return;

            const textToCopy = codeEl.textContent;
            
            try {
                await navigator.clipboard.writeText(textToCopy);
                
                // Success styling feedback
                const labelEn = btn.querySelector('.lang-en');
                const labelTh = btn.querySelector('.lang-th');
                const icon = btn.querySelector('i');

                const originalEn = labelEn.textContent;
                const originalTh = labelTh.textContent;
                const originalIconName = icon.getAttribute('data-lucide');

                // Update to success state
                labelEn.textContent = 'Copied!';
                labelTh.textContent = 'คัดลอกแล้ว!';
                btn.style.color = '#10b981'; // emerald green
                icon.setAttribute('data-lucide', 'check');
                if (typeof lucide !== 'undefined') lucide.createIcons();

                // Revert state after delay
                setTimeout(() => {
                    labelEn.textContent = originalEn;
                    labelTh.textContent = originalTh;
                    btn.style.color = '';
                    icon.setAttribute('data-lucide', originalIconName);
                    if (typeof lucide !== 'undefined') lucide.createIcons();
                }, 2000);

            } catch (err) {
                console.error('Failed to copy text: ', err);
            }
        });
    });
});
