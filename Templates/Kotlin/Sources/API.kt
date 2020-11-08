{% include "Includes/Header.stencil" %}

package {{ options.packageName }}

{% if info.description %}
/** {{ info.description }} */
{% endif %}
object {{ options.name }} {
    companion object {
        {% if info.version %}
        val version = "{{ info.version }}"
        {% endif %}
    }
    {% if tags %}

    {% for tag in tags %}
    val {{ options.tagPrefix }}{{ tag|lowerCamelCase }}{{ options.tagSuffix }}: {{ tag|upperCamelCase }}API by lazy { {{ tag|upperCamelCase }}API() }
    {% endfor %}
    {% endif %}
}
