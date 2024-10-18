const forms = u(".form-container")

forms.each(
    function (node, i) {
        const form = u(".form-content",node)
        const status = u(".form-status",node)
        form.handle('submit', 
            async function(e) {
                const formData = new FormData(form.first())
                console.log(formData)
                const uri = form.data("uri")
                const method = form.data("method")
                const success_uri = form.data("redirect-uri")
                const use_json = form.data("send-json") || form.data("send-json")===""
                console.log(use_json)
                status.removeClass("status-error")
                status.text("Please wait...")
                const response = await fetch(uri, {
                    method: method,
                    headers: {
                        ...(use_json && {"Content-Type": "application/json"})
                    },
                    body: use_json ? JSON.stringify(Object.fromEntries(formData.entries())) : formData
                })
                const data = await response.json()
                status.text(data.status)
                if (data.error) {
                    status.addClass("status-error")
                } else if (success_uri) {
                    const regex = /\{(.*)\}/g
                    const uri = success_uri.replace(regex,
                        function(str,part) {
                            return data[part] || "__error"
                        }
                    )
                    window.location.replace(uri)
                }
            }
        )
        
        const confirmation_inputs = u("input[data-field-equals]",node)
        confirmation_inputs.each(
            function (inp, i) {
                const self = u(inp)
                const referenced = u(`input[name="${self.data("field-equals")}"]`)
                self.handle("input",
                    function (e) {
                        if (referenced.first().value!==self.first().value) {
                            status.addClass("status-error")
                            status.text("Passwords do not match!")
                        } else {
                            status.removeClass("status-error")
                            status.text("")
                        }
                    }
                )
            }
        )

        const previews = u('img[data-preview]',node)
        previews.each(
            function (img, i) {
                const self = u(img)
                const referenced = u(`input[name="${self.data("preview")}"]`)
                console.log(referenced)
                referenced.handle("input",
                    function (e) {
                        const file = referenced.first().files[0]
                        console.log(img)
                        if (file) {
                            img.src = URL.createObjectURL(file)
                        }
                    }
                )
                referenced.trigger("input")
            }
        )
    }
)