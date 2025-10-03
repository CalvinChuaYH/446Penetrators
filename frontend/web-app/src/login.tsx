import { Button } from "@/components/ui/button"
import {
    Card,
    CardContent
} from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

function Login() {
  return (
    <div className="bg-gray-950 text-white min-h-screen flex flex-col items-center justify-center">
        <h1 className="text-3xl text-center py-8">Welcome to <span className="text-blue-500 font-extrabold">BestBlogs</span>.</h1>
        <Card className="w-full max-w-md bg-[#171717] border-[#373737]">
        <CardContent>
          <div className="flex flex-col gap-3 text-white">
            <form className="flex flex-col gap-6" onSubmit={() => {}}>
                <div className="grid gap-2">
                    <Label htmlFor="email">Email</Label>
                    <Input 
                    className="border-[#373737] bg-[#373737]" 
                    id="email" 
                    type="email" 
                    placeholder="test@example.com" 
                    required
                    value={""}
                    onChange={(e) => {}}
                    onKeyDown={() => {}}
                    />
                </div>

                <div className="grid gap-2">
                    <Label htmlFor="password">Password</Label>
                    <Input 
                    className="border-[#373737] bg-[#373737]" 
                    id="password" 
                    type="password" 
                    required
                    value={""}
                    onChange={(e) => {}}
                    onKeyDown={() => {}}
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