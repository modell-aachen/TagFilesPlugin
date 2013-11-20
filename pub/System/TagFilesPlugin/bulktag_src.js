jQuery(function($){
    // Disable checkboxes for disabled rows
    var livequeryDisabled = function(){
        var $this = $(this);
        $this.find('input[type=\"checkbox\"]').attr('disabled', 'disabled');
    }
    $('.bulkTagRowDisabled').livequery(livequeryDisabled);

    // add BulkTagUpdate input and UpdateTag css when checkbox changes in a row
    var changeCallback = function(){
        var $this = $(this);
        var $tr = $this.closest('tr');
        if(!$tr.hasClass('UpdateTag')) {
            $tr.addClass('UpdateTag');
            $tr.find('td:first').prepend('<input type=\"hidden\" name=\"'+$this.attr('name')+'\" value=\"BulkTagUpdate\"/>');
        }
    }
    var livequeryEnabled = function(){
        $(this).change(changeCallback);
    }
    $('.bulkTagRowEnabled input[type=\"checkbox\"]').livequery(livequeryEnabled);

    // When the form is being submitted, copy all changed rows to it
    $('form.BulkTagSubmitForm').livequery(function(){
        var $this = $(this);
        $this.submit(function(){
            var $form = $('form.BulkTag');
            var $newInputs = $('<div class=\"inputs\"></div>');
            $newInputs.hide();
            $newInputs.append($form.find('.UpdateTag').clone());
            $this.find('.inputs').replaceWith($newInputs);
        });
    });
});
