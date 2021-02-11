{% include "Common/Includes/Header.stencil" %}

package {{ options.packageName }}.model

{% for dependency in options.modelDependencies %}
import {{ dependency.path }}
{% endfor %}

{% include "Common/Includes/Model.stencil" %}
