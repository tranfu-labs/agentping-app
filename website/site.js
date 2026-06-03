(function () {
  const accessForm = document.querySelector("[data-access-form]");
  const protectedContent = document.querySelector("[data-protected-content]");
  const lockedContent = document.querySelector("[data-locked-content]");
  const accessError = document.querySelector("[data-access-error]");
  const accessCode = "agentping-team";
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function revealNode(node) {
    if (!node) return;
    node.classList.add("is-visible");
    node.querySelectorAll(".motion-item").forEach(function (item) {
      item.classList.add("is-visible");
    });
  }

  function unlockVpnPage() {
    if (protectedContent) {
      protectedContent.classList.remove("hidden");
      protectedContent.classList.add("unlocking");
      if (reducedMotion) {
        revealNode(protectedContent);
      } else {
        requestAnimationFrame(function () {
          revealNode(protectedContent);
        });
      }
    }
    if (lockedContent) lockedContent.classList.add("hidden");
  }

  if (protectedContent && window.localStorage.getItem("agentping-vpn-access") === "granted") {
    unlockVpnPage();
  }

  if (accessForm) {
    accessForm.addEventListener("submit", function (event) {
      event.preventDefault();
      const input = accessForm.querySelector("input");
      const value = input ? input.value.trim() : "";
      if (value === accessCode) {
        window.localStorage.setItem("agentping-vpn-access", "granted");
        unlockVpnPage();
      } else if (accessError) {
        accessError.textContent = "访问码不正确，请联系团队管理员确认。";
        accessForm.classList.remove("has-error");
        requestAnimationFrame(function () {
          accessForm.classList.add("has-error");
        });
      }
    });
  }

  function initMotion() {
    const targets = Array.from(
      document.querySelectorAll(
        ".hero-content, .hero-product, .page-title, .download-box, .access-panel"
          + ", .page-visual"
      )
    );

    if (!targets.length) return;

    targets.forEach(function (target, index) {
      target.classList.add("motion-item");
      target.style.setProperty("--motion-delay", Math.min(index % 6, 5) * 35 + "ms");
    });

    if (reducedMotion || !("IntersectionObserver" in window)) {
      targets.forEach(function (target) {
        target.classList.add("is-visible");
      });
      return;
    }

    document.body.classList.add("motion-ready");

    const observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { threshold: 0.08, rootMargin: "0px 0px -30px 0px" }
    );

    targets.forEach(function (target) {
      observer.observe(target);
    });
  }

  initMotion();
})();
