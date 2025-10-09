import { Button } from "@/components/ui/button"
import {
    Card,
    CardContent
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useState } from "react"
import { useNavigate } from "react-router-dom";

function Login() {
  const navigate = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");

  const handleUsernameChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setUsername(e.target.value);
  }

  const handlePasswordChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setPassword(e.target.value);
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleLogin(e as unknown as React.FormEvent);
    }
  }

  const encodedUsername = btoa(username); // built-in browser function
  const encodedPassword = btoa(password);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const response = await fetch('http://localhost:5000/auth/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ username: encodedUsername, password: encodedPassword }),
      });

      if (response.ok) {
        const data = await response.json();
        // console.log('Login successful:', data);
        localStorage.setItem('token', data.token);
        navigate('/home');
      } else {
        setUsername("");
        setPassword("");
        alert("Login failed.");
        // console.error('Login failed:', response.statusText);
        // Handle login failure (e.g., show error message)
      }
    } catch (error) {
      console.error('Error during login:', error);
    }
  }

  return (
    <div className="bg-gray-200 text-white min-h-screen flex flex-col items-center justify-center">
        <h1 className="text-3xl text-center py-8 text-black">Welcome to <span className="text-blue-500 font-extrabold">BestBlogs</span>.</h1>
        <Card className="w-full max-w-md bg-[#171717] border-[#373737]">
        <CardContent>
          <div className="flex flex-col gap-3 text-white">
            <form className="flex flex-col gap-6" onSubmit={handleLogin}>
                <div className="grid gap-2">
                    <Label htmlFor="email">Username</Label>
                    <Input 
                    className="border-[#373737] bg-[#373737]" 
                    id="username" 
                    type="text" 
                    placeholder="Enter your username" 
                    required
                    value={username}
                    onChange={handleUsernameChange}
                    onKeyDown={handleKeyDown}
                    />
                </div>

                <div className="grid gap-2">
                    <Label htmlFor="password">Password</Label>
                    <Input 
                    className="border-[#373737] bg-[#373737]" 
                    id="password" 
                    type="password" 
                    required
                    value={password}
                    onChange={handlePasswordChange}
                    onKeyDown={handleKeyDown}
                    />
                </div>
                
                <Button type="submit" variant="outline" className="bg-[#171717] border-[#373737]">
                    Login
                </Button>
            </form>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

export default Login;