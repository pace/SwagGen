{% include "Common/Includes/Header.stencil" %}

package {{ options.apiPackageName }}

import cloud.pace.sdk.api.API

{% if info.description %}
/** {{ info.description }} */
{% endif %}
object {{ options.name }} {

    const val VERSION = "{{ info.version }}"
    internal val baseUrl = "${API.baseUrl}/{{ options.urlPath }}/$VERSION/"

    {% if tags %}
    {% for tag in tags %}
    class {{ tag|upperCamelCase }}API
    {% endfor %}

    {% for tag in tags %}
    val API.{{ options.tagPrefix }}{{ tag|lowerCamelCase }}{{ options.tagSuffix }}: {{ tag|upperCamelCase }}API by lazy { {{ tag|upperCamelCase }}API() }
    {% endfor %}
    {% endif %}
}
