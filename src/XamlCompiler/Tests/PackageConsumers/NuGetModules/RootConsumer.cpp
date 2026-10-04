#if defined(XAML_IMPL_MODULE) || defined(XAML_USE_MODULE)
#error Ordinary consumers must not receive XamlC internal macros.
#endif
import NuGetModules.Application_Xaml;
template <typename D> using MainPageScaffold = winrt::NuGetModules::implementation::MainPageT<D>;
template <typename D> using EmptyPageScaffold = winrt::NuGetModules::implementation::EmptyPageT<D>;
template <typename D> using AppScaffold = winrt::NuGetModules::implementation::AppT<D>;
static_assert(sizeof(winrt::NuGetModules::implementation::XamlTypeInfoProvider) > 0);
