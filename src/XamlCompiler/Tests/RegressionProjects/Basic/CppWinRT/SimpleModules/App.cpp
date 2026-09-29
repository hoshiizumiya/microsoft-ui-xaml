// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
//
// App.xaml.cpp
// Implementation of the App class.
//

#include <windows.h>

import std;
import winrt.Windows.ApplicationModel;
import winrt.Windows.ApplicationModel.Activation;
import winrt.Microsoft.UI.Xaml.Navigation;
import winrt.Microsoft.UI.Xaml.Input;
import winrt.Simple.Models;

#include "App.h"
#include "MainPage.h"

using namespace ::winrt::Simple::implementation;

using namespace winrt;
using namespace winrt::Windows::ApplicationModel::Activation;
using namespace winrt::Windows::Foundation;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;
using namespace winrt::Microsoft::UI::Xaml::Interop;

// The Blank Application template is documented at http://go.microsoft.com/fwlink/?LinkId=402347&clcid=0x409

/// <summary>
/// Initializes the singleton application object.  This is the first line of authored code
/// executed, and as such is the logical equivalent of main() or WinMain().
/// </summary>
App::App()
{
    InitializeComponent();
    Suspending({ this, &App::OnSuspending });

#if defined _DEBUG && !defined DISABLE_XAML_GENERATED_BREAK_ON_UNHANDLED_EXCEPTION
    UnhandledException([this](IInspectable const&, ::Microsoft::UI::Xaml::UnhandledExceptionEventArgs const& e)
    {
        if (IsDebuggerPresent())
        {
            auto errorMessage = e.Message();
            __debugbreak();
        }
    });
#endif
}

/// <summary>
/// Invoked when the application is launched normally by the end user.	Other entry points
/// will be used such as when the application is launched to open a specific file.
/// </summary>
/// <param name="e">Details about the launch request and process.</param>
void App::OnLaunched(winrt::Microsoft::UI::Xaml::LaunchActivatedEventArgs const& e)
{
    Frame rootFrame(nullptr);
    auto content = Window::Current().Content();
    if (content)
    {
        rootFrame = content.try_as<Frame>();
    }

    if (rootFrame == nullptr)
    {
        rootFrame = Frame();

        rootFrame.NavigationFailed({ this, &App::OnNavigationFailed });

        if (e.UWPLaunchActivatedEventArgs().PreviousExecutionState() == ApplicationExecutionState::Terminated)
        {
        }

        if (e.UWPLaunchActivatedEventArgs().PrelaunchActivated() == false)
        {
            if (rootFrame.Content() == nullptr)
            {
                rootFrame.Navigate(xaml_typename<winrt::Simple::MainPage>(), winrt::box_value(e.Arguments()));
            }
            Window::Current().Content(rootFrame);
            Window::Current().Activate();
        }
    }
    else
    {
        if (e.UWPLaunchActivatedEventArgs().PrelaunchActivated() == false)
        {
            if (rootFrame.Content() == nullptr)
            {
                rootFrame.Navigate(xaml_typename<winrt::Simple::MainPage>(), winrt::box_value(e.Arguments()));
            }
            Window::Current().Activate();
        }
    }
}

void App::OnSuspending(winrt::Windows::Foundation::IInspectable const& sender, winrt::Windows::ApplicationModel::SuspendingEventArgs const& e)
{
    (void)sender;
    (void)e;
}

void App::OnNavigationFailed(winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::Navigation::NavigationFailedEventArgs const& e)
{
    std::wstring message(L"Failed to load Page ");
    throw hresult_error(E_FAIL, message.append(e.SourcePageType().Name));
}
