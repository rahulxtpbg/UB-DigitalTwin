window.HELP_IMPROVE_VIDEOJS = false;

/* ---- drag-to-compare slider ---- */
function initCompare() {
  var c = document.getElementById('compare');
  if (!c) return;
  var top = c.querySelector('.img-top');
  var divider = c.querySelector('.c-divider');
  var handle = c.querySelector('.c-handle');
  var dragging = false, pos = 50;
  function setPos(pct) {
    pos = Math.max(0, Math.min(100, pct));
    top.style.clipPath = 'inset(0 ' + (100 - pos) + '% 0 0)';
    divider.style.left = pos + '%';
    handle.style.left = pos + '%';
    if (handle) handle.setAttribute('aria-valuenow', Math.round(pos));
  }
  function fromEvent(e) {
    var rect = c.getBoundingClientRect();
    var x = (e.touches ? e.touches[0].clientX : e.clientX) - rect.left;
    setPos(x / rect.width * 100);
  }
  c.addEventListener('mousedown', function (e) { dragging = true; fromEvent(e); });
  window.addEventListener('mousemove', function (e) { if (dragging) fromEvent(e); });
  window.addEventListener('mouseup', function () { dragging = false; });
  c.addEventListener('touchstart', function (e) { dragging = true; fromEvent(e); }, { passive: true });
  c.addEventListener('touchmove', function (e) { if (dragging) fromEvent(e); }, { passive: true });
  c.addEventListener('touchend', function () { dragging = false; });
  // keyboard support on the handle (role="slider")
  if (handle) {
    handle.addEventListener('keydown', function (e) {
      var step = e.shiftKey ? 10 : 2;
      if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { setPos(pos - step); e.preventDefault(); }
      else if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { setPos(pos + step); e.preventDefault(); }
      else if (e.key === 'Home') { setPos(0); e.preventDefault(); }
      else if (e.key === 'End') { setPos(100); e.preventDefault(); }
    });
  }
  setPos(50);
}

$(document).ready(function() {
    // Check for click events on the navbar burger icon
    $(".navbar-burger").click(function() {
      // Toggle the "is-active" class on both the "navbar-burger" and the "navbar-menu"
      $(".navbar-burger").toggleClass("is-active");
      $(".navbar-menu").toggleClass("is-active");

    });

    var options = {
			slidesToScroll: 1,
			slidesToShow: 3,
			loop: true,
			infinite: true,
			autoplay: false,
			autoplaySpeed: 3000,
    }

		// Initialize all div with carousel class
    var carousels = bulmaCarousel.attach('.carousel', options);

    // Loop on each carousel initialized
    for(var i = 0; i < carousels.length; i++) {
    	// Add listener to  event
    	carousels[i].on('before:show', state => {
    		console.log(state);
    	});
    }

    // Access to bulmaCarousel instance of an element
    var element = document.querySelector('#my-element');
    if (element && element.bulmaCarousel) {
    	// bulmaCarousel instance is available as element.bulmaCarousel
    	element.bulmaCarousel.on('before-show', function(state) {
    		console.log(state);
    	});
    }

    bulmaSlider.attach();

    initCompare();

})
