// Direct consumer of the public XAML module contract. The root import is sufficient.
import XamlCppWinRTModulesSample.Application_Xaml;

static_assert(sizeof(winrt::XamlCppWinRTModulesSample::implementation::XamlBindings) > 0);
