document.addEventListener('DOMContentLoaded', function() {
  const columns = ['pending-tasks', 'active-tasks', 'paused-tasks'];
  const statusMap = {
    'pending-tasks': 'pending',
    'active-tasks': 'active',
    'paused-tasks': 'paused'
  };

  // Filter elements
  const filterProject = document.getElementById('filter-project');
  const filterTag = document.getElementById('filter-tag');
  const filterSearch = document.getElementById('filter-search');
  const filterClear = document.getElementById('filter-clear');

  // Initialize Sortable on columns
  columns.forEach(function(columnId) {
    const el = document.getElementById(columnId);
    if (!el) return;

    new Sortable(el, {
      group: 'runboard',
      animation: 150,
      ghostClass: 'runboard-card-ghost',
      chosenClass: 'runboard-card-chosen',
      dragClass: 'runboard-card-drag',
      filter: '.runboard-card-hidden',
      onEnd: function(evt) {
        const taskId = evt.item.dataset.taskId;
        const newColumnId = evt.to.id;
        const newStatus = statusMap[newColumnId];

        updateTaskStatus(taskId, newStatus, evt);
      }
    });
  });

  // Filter event listeners
  if (filterProject) {
    filterProject.addEventListener('change', applyFilters);
  }
  if (filterTag) {
    filterTag.addEventListener('change', applyFilters);
  }
  if (filterSearch) {
    filterSearch.addEventListener('input', applyFilters);
  }
  if (filterClear) {
    filterClear.addEventListener('click', clearFilters);
  }

  function applyFilters() {
    // Read current filter values fresh
    var projectFilter = '';
    var tagFilter = '';
    var searchFilter = '';

    if (filterProject) {
      projectFilter = filterProject.value.toLowerCase();
    }
    if (filterTag) {
      tagFilter = filterTag.value.toLowerCase();
    }
    if (filterSearch) {
      searchFilter = filterSearch.value.toLowerCase().trim();
    }

    var allCards = document.querySelectorAll('.runboard-card');
    var visibleCount = 0;

    // First pass: reset all cards to visible
    allCards.forEach(function(card) {
      card.classList.remove('runboard-card-hidden');
    });

    // Second pass: hide cards that don't match filters
    allCards.forEach(function(card) {
      var cardProject = (card.dataset.project || '').toLowerCase();
      var cardTags = (card.dataset.tags || '').toLowerCase();
      var cardSearchable = (card.dataset.searchable || '').toLowerCase();

      var shouldHide = false;

      // Project filter - hide if doesn't match
      if (projectFilter !== '' && cardProject !== projectFilter) {
        shouldHide = true;
      }

      // Tag filter - hide if doesn't contain tag
      if (!shouldHide && tagFilter !== '') {
        var tagsArray = cardTags.split(',').map(function(t) { return t.trim(); });
        if (tagsArray.indexOf(tagFilter) === -1) {
          shouldHide = true;
        }
      }

      // Search filter - hide if doesn't match search text
      if (!shouldHide && searchFilter !== '') {
        if (cardSearchable.indexOf(searchFilter) === -1) {
          shouldHide = true;
        }
      }

      if (shouldHide) {
        card.classList.add('runboard-card-hidden');
      } else {
        visibleCount++;
      }
    });

    updateColumnCounts();
    updateVisibleCount(visibleCount);
  }

  function clearFilters() {
    if (filterProject) filterProject.value = '';
    if (filterTag) filterTag.value = '';
    if (filterSearch) filterSearch.value = '';
    applyFilters();
  }

  function updateVisibleCount(count) {
    const visibleEl = document.getElementById('visible-count');
    if (visibleEl) {
      visibleEl.textContent = count;
    }
  }

  function updateTaskStatus(taskId, newStatus, evt) {
    const card = evt.item;
    card.classList.add('runboard-card-updating');

    fetch('/tasks/' + taskId + '/status', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'status=' + encodeURIComponent(newStatus)
    })
    .then(function(response) {
      return response.json().then(function(data) {
        return { ok: response.ok, data: data };
      });
    })
    .then(function(result) {
      card.classList.remove('runboard-card-updating');
      if (!result.ok) {
        showError(result.data.message || 'Failed to update task');
        // Revert the move by reloading
        location.reload();
      } else {
        updateColumnCounts();
      }
    })
    .catch(function(error) {
      card.classList.remove('runboard-card-updating');
      showError('Network error: ' + error.message);
      location.reload();
    });
  }

  function updateColumnCounts() {
    columns.forEach(function(columnId) {
      const el = document.getElementById(columnId);
      if (!el) return;
      const count = el.querySelectorAll('.runboard-card:not(.runboard-card-hidden)').length;
      const column = el.closest('.runboard-column');
      const countEl = column.querySelector('.column-count');
      if (countEl) {
        countEl.textContent = count;
      }
    });
  }

  function showError(message) {
    const container = document.querySelector('.main-container');
    const existingFlash = container.querySelector('.flash-error');
    if (existingFlash) {
      existingFlash.remove();
    }
    const flash = document.createElement('div');
    flash.className = 'flash-error';
    flash.innerHTML = '<span class="flash-label">ERR:</span> ' + escapeHtml(message);
    container.insertBefore(flash, container.firstChild.nextSibling);
    setTimeout(function() {
      flash.remove();
    }, 5000);
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
});
