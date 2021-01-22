{% include "Includes/Header.stencil" %}

package {{ options.apiPackageName }}

import java.text.SimpleDateFormat
import java.util.*

{% if info.description %}
/** {{ info.description }} */
{% endif %}
object {{ options.name }} {

    {% if info.version %}
    const val VERSION = "{{ info.version }}"
    {% endif %}
    var baseUrl: String = ""
    var apiKey: String = ""
    var additionalHeaders: Map<String, String> = emptyMap()

    {% if tags %}
    {% for tag in tags %}
    class {{ tag|upperCamelCase }}API
    {% endfor %}

    {% for tag in tags %}
    val {{ options.tagPrefix }}{{ tag|lowerCamelCase }}{{ options.tagSuffix }}: {{ tag|upperCamelCase }}API by lazy { {{ tag|upperCamelCase }}API() }
    {% endfor %}
    {% endif %}
    
    fun setupAPI(baseUrl: String, apiKey: String, additionalHeaders: Map<String, String>) {
        this.baseUrl = baseUrl
        this.apiKey = apiKey
        this.additionalHeaders = additionalHeaders
    }
    
    
    fun Date.toIso8601(): String {
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).run {
            timeZone = TimeZone.getTimeZone("UTC")
            format(this@toIso8601)
        }
    }
}
