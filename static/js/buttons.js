const toggles = u("button[data-toggle],button[data-action]")

toggles.each(
    function (b, i) {
        const ub = u(b)
        if (ub.data("dialog")) {
            ub.addClass('material-icons')
            b.textContent = ub.data(ub.data("toggle")==="on" ? "on-icon" : "off-icon")
            ub.on('click',
                async function(e) {
                    const old_toggle = ub.data("toggle")==="on"
                    const toggle = !old_toggle
                    ub.data("toggle",toggle ? "on" : "off")
                    b.textContent = ub.data(toggle ? "on-icon" : "off-icon")
                    const dial = u(`dialog#${ub.data("dialog")}`)
                    if (toggle) {
                        dial.first().show()
                    } else {
                        dial.first().close()
                    }
                }
            )
        } else if (ub.data("action")!==null) {
            ub.on('click',
            async function(e) {
                const response = await fetch(ub.data("uri"), {
                    method: ub.data("method"),
                    headers: {
                        "Content-Type": "application/json"
                    },
                    body: ub.data("value")
                })
                const data = await response.json()
                if (!data.error && ub.data("redirect-uri")) {
                    const regex = /\{(.*)\}/g
                    const uri = ub.data("redirect-uri").replace(regex,
                        function(str,part) {
                            return data[part] || "__error"
                        }
                    )
                    window.location.replace(uri)
                }
            })
        } else {
            ub.addClass('material-icons')
            b.textContent = ub.data(ub.data("toggle")==="on" ? "on-icon" : "off-icon")
            ub.on('click', 
                async function(e) {
                    const old_toggle = ub.data("toggle")==="on"
                    const toggle = !old_toggle
                    const response = await fetch(ub.data("uri"), {
                        method: ub.data("method"),
                        headers: {
                            "Content-Type": "application/json"
                        },
                        body: toggle ? ub.data("on-value") : ub.data("off-value")
                    })
                    const data = await response.json()
                    if (!data.error) {
                        ub.data("toggle",toggle ? "on" : "off")
                        b.textContent = ub.data(toggle ? "on-icon" : "off-icon")
                    }
                }
            )
        }
    }
)
